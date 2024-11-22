import Vapor
import FluentKit
// swiftlint:disable cyclomatic_complexity file_length function_body_length
final class WebSocketManager: @unchecked Sendable {

    static let shared = WebSocketManager()
    private var connections: [UUID: [UserConnection]] = [:]

    private init() {}
    
    func handleUserClosedConnection(socket: WebSocket, req: Request) async {
        guard let connectionRoomID = connections.first(where: { $0.value.contains(where: { $0.socket === socket }) })?.key else {
            return
        }
        do {
            let room = try await fetchRoom(roomID: connectionRoomID, db: req.db)
            if room.gameStatus == GameStatus.waiting.rawValue || room.gameStatus == GameStatus.ready.rawValue {
                await handleLeaveRoom(socket: socket, roomID: connectionRoomID, db: req.db)
            } else {
                await handleLeaveGame(socket: socket, roomID: connectionRoomID, db: req.db)
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    func receiveMessage(from socket: WebSocket, incomingMessage: IncomingMessage, req: Request) async {
        await handleIncomingMessage(socket: socket, incomingMessage: incomingMessage, req: req)
    }

    func sendMessage(to connections: [UserConnection]?, outcomingMessage: OutcomingMessage) {
        guard let connections, let message = encodeMessage(outcomingMessage) else { return }
        for connection in connections {
            connection.socket.send(message)
        }
    }

    func sendError(to sockets: [WebSocket]?, message: String) {
        let outcomingMessage = OutcomingMessage(
            event: .error,
            errorMessage: message
        )
        guard let sockets, let message = encodeMessage(outcomingMessage) else { return }
        for socket in sockets {
            socket.send(message)
        }
    }
}

// MARK: - Private

extension WebSocketManager {

    private func handleIncomingMessage(socket: WebSocket, incomingMessage: IncomingMessage, req: Request) async {
        do {
            switch incomingMessage.action {
            case .joinRoom:
                let userService = UserService(db: req.db)
                let userID = try await userService.fetchUserID(req: req)
                await handleJoinRoom(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    userID: userID,
                    db: req.db
                )
            case .changeRoomPrivacy:
                await handleChangeRoomPrivacy(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .kickPlayer:
                guard let kickPlayerID = incomingMessage.kickPlayerID else {
                    sendError(to: [socket], message: "KickPlayerID is missing")
                    return
                }
                await handleKickPlayer(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    kickPlayerID: kickPlayerID,
                    db: req.db
                )
            case .leaveRoom:
                await handleLeaveRoom(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .startGame:
                await handleStartGame(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .exchangeTiles:
                guard let changingTiles = incomingMessage.changingTiles else {
                    sendError(to: [socket], message: "ChangingTilesIndexes are missing")
                    return
                }
                await handleExchangeTiles(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    changingTiles: changingTiles,
                    db: req.db
                )
            case .suggestToEndGame:
                await handleEndGameSuggestion(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .pauseGame:
                await handlePauseGame(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .resumeGame:
                await handleResumeGame(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .skipTurn:
                await handleEndTurn(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    emptyTurn: true,
                    db: req.db
                )
            case .endTurn:
                await handleEndTurn(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    emptyTurn: false,
                    db: req.db
                )
            case .placeWord:
                guard
                    let direction = incomingMessage.direction,
                    let letters = incomingMessage.letters else {
                    sendError(to: [socket], message: "Direction or letters are missing")
                    return
                }
                await handlePlaceWord(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    direction: direction,
                    letters: letters,
                    db: req.db
                )
            case .leaveGame:
                await handleLeaveGame(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .sendReaction:
                guard let reaction = incomingMessage.reaction, reaction.count <= 15 else {
                    sendError(to: [socket], message: "Reaction is missing or invalid")
                    return
                }
                await handleSendReaction(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    reaction: reaction,
                    db: req.db
                )
            }
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }
}

// MARK: - Action Handlers

extension WebSocketManager {

    private func handleJoinRoom(
        socket: WebSocket,
        roomID: UUID,
        userID: UUID,
        db: Database
    ) async {
        do {
            guard !isSocketConnected(to: roomID, socket: socket) else {
                sendError(to: [socket], message: "Socket is already connected to the room")
                return
            }
            
            let userName = try await fetchUsername(for: userID, on: db)
            let room = try await fetchRoomWithPlayersAndAdmin(roomID: roomID, db: db)
            
            let isUserInRoom = room.players.contains { $0.$player.id == userID }
            guard isUserInRoom else {
                sendError(to: [socket], message: "User is not a valid player in this room")
                return
            }

            let connection = addConnection(roomID: roomID, userID: userID, socket: socket)
            sendMessage(to: [connection], outcomingMessage: OutcomingMessage(event: .joinedRoom))

            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .playerJoined,
                    newPlayerInfo: PlayerInfo(id: userID, name: userName)
                )
            )

            guard let adminConnection = otherConnections?.first(where: { $0.userID == room.$admin.id }) else {
                return
            }

            if room.players.count == room.maxPlayers {
                sendMessage(
                    to: [adminConnection],
                    outcomingMessage: OutcomingMessage(event: .roomReady)
                )
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleChangeRoomPrivacy(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomIfAdmin(roomID: roomID, userID: userID, db: db)
            try validateGameState(room, validStates: [GameStatus.waiting.rawValue, GameStatus.ready.rawValue])

            room.isPrivate.toggle()
            try await room.update(on: db)

            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(
                    event: .roomChangedPrivacy,
                    newRoomPrivacy: room.isPrivate
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleKickPlayer(
        socket: WebSocket,
        roomID: UUID,
        kickPlayerID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomIfAdmin(roomID: roomID, userID: userID, db: db)
            try validateGameState(room, validStates: [GameStatus.waiting.rawValue, GameStatus.ready.rawValue])
            try validateKickPlayerID(kickPlayerID: kickPlayerID, userID: userID, roomID: roomID)

            let initialGameStatus = room.gameStatus

            try await db.transaction { db in
                try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .filter(\.$player.$id == kickPlayerID)
                    .delete()

                let playerCount = try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .count()

                if room.gameStatus == GameStatus.ready.rawValue && playerCount < room.maxPlayers {
                    room.gameStatus = GameStatus.waiting.rawValue
                    try await room.update(on: db)
                }
            }

            if let kickPlayerConnection = connections[roomID]?.first(where: { $0.userID == kickPlayerID }) {
                sendMessage(
                    to: [kickPlayerConnection],
                    outcomingMessage: OutcomingMessage(event: .kickedByAdmin)
                )
                try await kickPlayerConnection.socket.close()
                removeConnection(for: kickPlayerConnection.socket, roomID: roomID)
                sendMessage(
                    to: connections[roomID],
                    outcomingMessage: OutcomingMessage(
                        event: .playerKicked,
                        kickedPlayerID: kickPlayerID
                    )
                )
            }

            if room.gameStatus != initialGameStatus,
                let adminConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [adminConnection],
                    outcomingMessage: OutcomingMessage(event: .roomWaiting)
                )
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleLeaveRoom(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoom(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.waiting.rawValue, GameStatus.ready.rawValue])

            let initialGameStatus = room.gameStatus
            let adminLeft = userID == room.$admin.id

            let remainingPlayers = try await db.transaction { db -> [RoomPlayer] in
                try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .filter(\.$player.$id == userID)
                    .delete()

                let players = try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .all()

                if room.gameStatus == GameStatus.ready.rawValue && players.count < room.maxPlayers {
                    room.gameStatus = GameStatus.waiting.rawValue
                }

                if adminLeft, let newAdmin = players.first {
                    room.$admin.id = newAdmin.$player.id
                }

                if players.isEmpty {
                    try await room.delete(on: db)
                } else {
                    try await room.update(on: db)
                }

                return players
            }

            if let leavingPlayerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [leavingPlayerConnection],
                    outcomingMessage: OutcomingMessage(event: .leftRoom)
                )
                try await leavingPlayerConnection.socket.close()
                removeConnection(for: leavingPlayerConnection.socket, roomID: roomID)
            }

            if remainingPlayers.isEmpty {
                if let roomConnections = connections[roomID] {
                    for connection in roomConnections {
                        try await connection.socket.close()
                    }
                    connections[roomID] = nil
                }
            } else {
                let message = adminLeft
                ? OutcomingMessage(
                    event: .playerLeftRoom,
                    leftPlayerID: userID,
                    newAdminID: room.$admin.id
                )
                : OutcomingMessage(
                    event: .playerLeftRoom,
                    leftPlayerID: userID
                )

                sendMessage(to: connections[roomID], outcomingMessage: message)

                if room.gameStatus != initialGameStatus,
                    let adminConnection = connections[roomID]?.first(where: { $0.userID == room.$admin.id }) {
                    sendMessage(
                        to: [adminConnection],
                        outcomingMessage: OutcomingMessage(event: .roomWaiting)
                    )
                }
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleExchangeTiles(
        socket: WebSocket,
        roomID: UUID,
        changingTiles: [Int],
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoom(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue])
            try validatePlayerTurn(room: room, userID: userID)
            try validateTilesLeft(room: room)
            try validateChangingTilesCount(changingTiles.count)

            // returning tiles to bag
            for index in changingTiles {
                if let currentTile = room.playersTiles[userID.uuidString]?[index],
                   let currentTileLeftCount = room.tilesLeft[currentTile] {
                    room.tilesLeft[currentTile] = currentTileLeftCount + 1
                }
            }

            // giving new tiles to player
            var tilesLeft = room.tilesLeft
            let playerTiles = redistributeTiles(
                to: userID,
                withTiles: room.playersTiles[userID.uuidString]!,
                onIndexes: changingTiles,
                using: &tilesLeft
            )

            // updating room
            room.playersTiles[userID.uuidString] = playerTiles
            room.currentTurnIndex = (room.currentTurnIndex + 1) % room.turnOrder.count
            room.tilesLeft = tilesLeft
            try await room.update(on: db)

            // noticing player about his new tiles
            if let playerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [playerConnection],
                    outcomingMessage: OutcomingMessage(
                        event: .exhangedTiles,
                        currentTurn: room.turnOrder[room.currentTurnIndex],
                        playerTiles: playerTiles
                    )
                )
            }

            // noticing other players about another's player exhanging turn
            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .playerExchangedTiles,
                    exchangedTilesPlayerID: userID,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleEndGameSuggestion(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoom(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue])
            try validatePlayerTurn(room: room, userID: userID)
            try validateSkippedTurns(for: room)

            // Noticing players about end of the game because of 6 empty turns
            if let winnerID = UUID(uuidString: room.leaderboard.max(by: { $0.value < $1.value })?.key ?? ""),
               let playersConnections = connections[roomID] {
                sendMessage(
                    to: playersConnections,
                    outcomingMessage: OutcomingMessage(
                        event: .gameEndedMuchEmptyTurns,
                        winnerID: winnerID
                    )
                )
            }

            // Changing gameStatus to .waiting
            room.gameStatus = GameStatus.waiting.rawValue

            // Reseting all room statistics
            room.reset()
            try await room.update(on: db)
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleEndTurn(
        socket: WebSocket,
        roomID: UUID,
        emptyTurn: Bool,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoom(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue])
            try validatePlayerTurn(room: room, userID: userID)

            if emptyTurn {
                room.currentSkippedTurns += 1
            } else {
                room.currentSkippedTurns = 0
            }
            try await room.update(on: db)

            guard let playerTiles = room.playersTiles[userID.uuidString] else { return }

            // Moved to the next turn
            room.currentTurnIndex = (room.currentTurnIndex + 1) % room.turnOrder.count
            try await room.update(on: db)

            // Notice player about his turn
            if let playerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [playerConnection],
                    outcomingMessage: OutcomingMessage(
                        event: .endedTurn,
                        currentTurn: room.turnOrder[room.currentTurnIndex],
                        playerTiles: playerTiles
                    )
                )
            }

            // Notice other players about the turn
            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .playerEndedTurn,
                    endedTurnPlayerID: userID,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handlePlaceWord(
        socket: WebSocket,
        roomID: UUID,
        direction: Direction,
        letters: [LetterPlacement],
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoom(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue])
            try validatePlayerTurn(room: room, userID: userID)

            guard var playerTiles = room.playersTiles[userID.uuidString] else { return }

            let gameService = WordGameService()
            let word = letters.buildWord(with: playerTiles, direction: direction)

            guard try await gameService.isValidWord(word, on: db) else {
                throw Abort(.badRequest, reason: "The word '\(word)' is invalid")
            }

            if room.placedWords.count == 0 {
                try validateFirstWordPlacement(letters: letters)
            }

            var board = room.board

            // Checking words around new word
            _ = gameService.findAllWords(
                from: letters,
                forWord: word,
                direction: direction,
                board: board
            )

            // Placing new word on the board
            let sameLetterCount = try gameService.placeLetters(
                from: letters,
                withTiles: playerTiles,
                board: &board
            )
            if room.placedWords.count > 0 {
                guard sameLetterCount > 0 else {
                    throw Abort(.badRequest, reason: "New word should cross any other word on the board")
                }
            }

            // Giving new tiles to player
            var tilesLeft = room.tilesLeft
            playerTiles = redistributeTiles(
                to: userID,
                withTiles: playerTiles,
                onIndexes: letters.getIndexes(),
                using: &tilesLeft
            )

            // Count player's score for new word
            let playerScore = gameService.calculateScore(
                letters: letters,
                board: board,
                boardLayout: BoardLayoutProvider.shared.layout,
                tileWeights: LettersInfoProvider.shared.initialWeights()
            )

            // Recalculate leaderboard
            if let currentScore = room.leaderboard[userID.uuidString] {
                room.leaderboard[userID.uuidString] = currentScore + playerScore
            }

            // Update room in DB
            room.playersTiles[userID.uuidString] = playerTiles
            room.tilesLeft = tilesLeft
            room.placedWords.append(word)
            room.board = board
            try await room.update(on: db)

            if playerTiles.isEmpty && room.tilesLeft.keys.isEmpty {

                // Notice everyone about win
                if let playersConnections = connections[roomID] {
                    sendMessage(
                        to: playersConnections,
                        outcomingMessage: OutcomingMessage(
                            event: .gameEndedPlayerWinned,
                            winnerID: userID
                        )
                    )
                }

                // Change gameStatus to .waiting
                room.gameStatus = GameStatus.waiting.rawValue

                // Reset all room statistics
                room.reset()
                try await room.update(on: db)

                return
            }

            // Notice player about his points for thiw word
            if let playerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [playerConnection],
                    outcomingMessage: OutcomingMessage(
                        event: .placedWord,
                        newWord: word,
                        scoredPoints: playerScore,
                        playerTiles: playerTiles
                    )
                )
            }

            // Notice other players about the turn
            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .playerPlacedWord,
                    placedWordPlayerID: userID,
                    newWord: word
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleWin(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) {

    }

    private func handleStartGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomIfAdmin(roomID: roomID, userID: userID, db: db)
            try validateGameState(room, validStates: [GameStatus.waiting.rawValue, GameStatus.ready.rawValue])

            let boardSize = BoardLayoutProvider.shared.size
            let boardLayout = BoardLayoutProvider.shared.layout
            let boardString = String(repeating: ".", count: boardSize * boardSize)

            let roomPlayers = try await room.$players.query(on: db).with(\.$player).all()
            let roomPlayersMap = Dictionary(uniqueKeysWithValues: roomPlayers.map { ($0.$player.id, $0) })

            let turnOrder = roomPlayersMap.keys.shuffled()

            let leaderboard = Dictionary(uniqueKeysWithValues: turnOrder.map { ($0.uuidString, 0) })

            var tilesLeft = LettersInfoProvider.shared.initialQuantities()
            let playersTiles = distributeTiles(to: turnOrder, using: &tilesLeft)

            let tilesLeftCopy = tilesLeft

            room.board = boardString
            room.turnOrder = turnOrder
            room.leaderboard = leaderboard
            room.tilesLeft = tilesLeftCopy
            room.playersTiles = playersTiles
            room.gameStatus = GameStatus.started.rawValue
            try await room.update(on: db)

            for playerID in turnOrder {
                let playerTiles = playersTiles[playerID.uuidString]

                let message = OutcomingMessage(
                    event: .gameStarted,
                    boardLayout: boardLayout,
                    currentTurn: turnOrder[room.currentTurnIndex],
                    playerTiles: playerTiles
                )

                guard let currentConnection = connections[roomID]?.first(where: { $0.userID == playerID }) else {
                    return
                }
                sendMessage(to: [currentConnection], outcomingMessage: message)
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handlePauseGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomIfAdmin(roomID: roomID, userID: userID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue])

            room.gameStatus = GameStatus.paused.rawValue
            try await room.update(on: db)

            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(event: .gamePaused)
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleResumeGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomIfAdmin(roomID: roomID, userID: userID, db: db)
            try validateGameState(room, validStates: [GameStatus.paused.rawValue])

            room.gameStatus = GameStatus.started.rawValue
            try await room.update(on: db)

            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(
                    event: .gameResumed,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleSendReaction(
        socket: WebSocket,
        roomID: UUID,
        reaction: String,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)

            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(
                    event: .reactionSent,
                    reaction: reaction,
                    senderID: userID
                )
            )
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }

    private func handleLeaveGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            try validateSocketConnection(socket: socket, roomID: roomID)
            let userID = try extractUserID(from: socket, in: roomID)
            let room = try await fetchRoomWithPlayersAndAdmin(roomID: roomID, db: db)
            try validateGameState(room, validStates: [GameStatus.started.rawValue, GameStatus.paused.rawValue])

            let adminLeft = userID == room.$admin.id

            let remainingPlayers = try await db.transaction { db -> [RoomPlayer] in
                try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .filter(\.$player.$id == userID)
                    .delete()

                if let playerTiles = room.playersTiles[userID.uuidString] {
                    for tile in playerTiles {
                        room.tilesLeft[tile, default: 0] += 1
                    }
                    room.playersTiles.removeValue(forKey: userID.uuidString)
                }

                room.leaderboard.removeValue(forKey: userID.uuidString)
                room.turnOrder.removeAll(where: { $0 == userID })

                let players = try await RoomPlayer.query(on: db).filter(\.$room.$id == roomID).all()

                if adminLeft, let newAdmin = players.first {
                    room.$admin.id = newAdmin.$player.id
                }
                if !players.isEmpty {
                    room.currentTurnIndex = room.currentTurnIndex % players.count
                }

                try await room.update(on: db)
                return players
            }

            if let leavingPlayerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [leavingPlayerConnection],
                    outcomingMessage: OutcomingMessage(event: .leftGame)
                )
                try await leavingPlayerConnection.socket.close()
                removeConnection(for: leavingPlayerConnection.socket, roomID: roomID)

                let message = adminLeft
                ? OutcomingMessage(
                    event: .playerLeftGame,
                    leftPlayerID: userID,
                    currentTurn: room.turnOrder[room.currentTurnIndex],
                    newAdminID: room.$admin.id
                )
                : OutcomingMessage(
                    event: .playerLeftGame,
                    leftPlayerID: userID,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )

                sendMessage(to: connections[roomID], outcomingMessage: message)
            }

            if remainingPlayers.count == 1, let winner = remainingPlayers.first {
                room.reset()
                try await room.update(on: db)

                let winnerID = winner.$player.id

                sendMessage(
                    to: connections[roomID],
                    outcomingMessage: OutcomingMessage(
                        event: .gameEndedSoloInRoom,
                        winnerID: winnerID
                    )
                )
            }

            if remainingPlayers.count == 0 {
                try await room.delete(on: db)
                if let roomConnections = connections[roomID] {
                    for connection in roomConnections {
                        try await connection.socket.close()
                    }
                }
                connections[roomID] = nil
            }
        } catch let error as Abort {
            sendError(to: [socket], message: error.reason)
        } catch {
            sendError(to: [socket], message: error.localizedDescription)
        }
    }
}

extension WebSocketManager {

    private func addConnection(roomID: UUID, userID: UUID, socket: WebSocket) -> UserConnection {
        let newConnection = UserConnection(userID: userID, socket: socket)
        connections[roomID, default: []].append(newConnection)
        return newConnection
    }
    
    private func removeConnection(for socket: WebSocket, roomID: UUID? = nil) {
        if let roomID {
            connections[roomID]?.removeAll { $0.socket === socket }
            if connections[roomID]?.isEmpty == true {
                connections.removeValue(forKey: roomID)
            }
        } else {
            for roomID in connections.keys {
                connections[roomID]?.removeAll { $0.socket === socket }
                if connections[roomID]?.isEmpty == true {
                    connections.removeValue(forKey: roomID)
                }
            }
        }
    }

    private func isSocketConnected(to roomID: UUID, socket: WebSocket) -> Bool {
        guard let connections = connections[roomID] else {
            return false
        }
        return connections.contains { $0.socket === socket }
    }

    private func validateSocketConnection(socket: WebSocket, roomID: UUID) throws {
        guard let connections = connections[roomID], connections.contains(where: { $0.socket === socket }) else {
            throw Abort(
                .badRequest,
                reason: "No connection found or the current connection is not associated with the room"
            )
        }
    }

    private func extractUserID(from socket: WebSocket, in roomID: UUID) throws -> UUID {
        guard let userID = connections[roomID]?.first(where: { $0.socket === socket })?.userID else {
            throw Abort(.badRequest, reason: "User ID could not be found for the specified connection in the room")
        }
        return userID
    }

    private func fetchRoomIfAdmin(roomID: UUID, userID: UUID, db: Database) async throws -> Room {
        guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
            throw Abort(.forbidden, reason: "You are not the admin of this room or the room does not exist")
        }
        return room
    }

    private func fetchRoom(roomID: UUID, db: Database) async throws -> Room {
        guard let room = try await Room.query(on: db)
            .with(\.$players)
            .filter(\.$id == roomID)
            .first() else {
            throw Abort(.notFound, reason: "Room with the specified ID was not found")
        }
        return room
    }

    func fetchRoomWithPlayersAndAdmin(roomID: UUID, db: Database) async throws -> Room {
        guard let room = try await Room.query(on: db)
            .with(\.$players)
            .with(\.$admin)
            .filter(\.$id == roomID)
            .first() else {
            throw Abort(.notFound, reason: "Room with the specified ID was not found")
        }
        return room
    }
    
    func fetchUsername(for userID: UUID, on db: Database) async throws -> String {
        if let username = try await User.find(userID, on: db)?.username {
            return username
        } else {
            throw Abort(.notFound, reason: "Username not found for the given user ID")
        }
    }
    
    private func validateGameState(_ room: Room, validStates: [String]) throws {
        guard validStates.contains(room.gameStatus) else {
            throw Abort(.badRequest, reason: "Game is not in a valid state for this action")
        }
    }

    private func validateKickPlayerID(kickPlayerID: UUID, userID: UUID, roomID: UUID) throws {
        guard kickPlayerID != userID else {
            throw Abort(.forbidden, reason: "The admin cannot kick themselves from the room")
        }
        guard connections[roomID]?.contains(where: { $0.userID == kickPlayerID }) == true else {
            throw Abort(.badRequest, reason: "The specified player is not part of the room")
        }
    }

    private func validatePlayerTurn(room: Room, userID: UUID) throws {
        guard room.turnOrder[room.currentTurnIndex] == userID else {
            throw Abort(.forbidden, reason: "It is another player's turn")
        }
    }

    private func validateTilesLeft(room: Room, minimumTiles: Int = 7) throws {
        let totalTilesLeft = room.tilesLeft.values.reduce(0, +)
        guard totalTilesLeft >= minimumTiles else {
            throw Abort(.badRequest, reason: "There must be at least \(minimumTiles) tiles left")
        }
    }

    private func validateChangingTilesCount(_ count: Int, min: Int = 1, max: Int = 7) throws {
        guard count >= min && count <= max else {
            throw Abort(.badRequest, reason: "You can exchange between \(min) and \(max) tiles")
        }
    }

    private func validateSkippedTurns(for room: Room, requiredTurns: Int = 6) throws {
        guard room.currentSkippedTurns >= requiredTurns else {
            throw Abort(
                .badRequest,
                reason: "The game can't be ended yet. Minimum \(requiredTurns) skipped turns are required"
            )
        }
    }

    private func validateFirstWordPlacement(letters: [LetterPlacement], centerPosition: [Int] = [7, 7]) throws {
        guard letters.contains(where: { $0.position == centerPosition }) else {
            throw Abort(
                .badRequest,
                reason: "The first word on the board must cover the center position \(centerPosition)"
            )
        }
    }

    private func redistributeTiles(
        to player: UUID,
        withTiles playerTiles: [String],
        onIndexes changingTiles: [Int],
        using tiles: inout [String: Int]
    ) -> [String] {
        var newPlayerTiles = playerTiles
        var remainingChangingTiles = changingTiles

        let totalTilesAvailable = tiles.values.reduce(0, +)
        if totalTilesAvailable < changingTiles.count {
            remainingChangingTiles = Array(changingTiles.prefix(totalTilesAvailable))
        }

        for index in Array(changingTiles.suffix(changingTiles.count - remainingChangingTiles.count)) {
            newPlayerTiles[index] = ""
        }

        for index in remainingChangingTiles {
            guard let randomLetter = tiles.keys.randomElement() else { break }

            newPlayerTiles[index] = randomLetter
            if let count = tiles[randomLetter], count > 1 {
                tiles[randomLetter] = count - 1
            } else {
                tiles.removeValue(forKey: randomLetter)
            }
        }

        return newPlayerTiles.filter { !$0.isEmpty }
    }

    private func distributeTiles(to players: [UUID], using tiles: inout [String: Int]) -> [String: [String]] {
        var playersTiles: [String: [String]] = [:]

        for playerID in players {
            var playerTiles: [String] = []

            while playerTiles.count < 7 && !tiles.isEmpty {
                guard let randomLetter = tiles.keys.randomElement() else { break }
                playerTiles.append(randomLetter)
                if let count = tiles[randomLetter], count > 1 {
                    tiles[randomLetter] = count - 1
                } else {
                    tiles.removeValue(forKey: randomLetter)
                }
            }

            playersTiles[playerID.uuidString] = playerTiles
        }

        return playersTiles
    }

    private func encodeMessage<T: Codable>(_ message: T) -> String? {
        do {
            let jsonData = try JSONEncoder().encode(message)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
