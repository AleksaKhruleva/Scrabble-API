import Vapor
import FluentKit

final class WebSocketManager: @unchecked Sendable {
    
    static let shared = WebSocketManager()
    private var connections: [UUID: [UserConnection]] = [:]
    
    private init() {}
    
    func removeConnection(for socket: WebSocket, roomID: UUID? = nil) {
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
    
    func receiveMessage(from socket: WebSocket, incomingMessage: IncomingMessage, req: Request) async {
        await handleIncomingMessage(socket: socket, incomingMessage: incomingMessage, req: req)
    }
    
    // TODO: Сделать ли отдельный метод для отправки ошибки ???
    
    func sendMessage(to connections: [UserConnection]?, outcomingMessage: OutcomingMessage) {
        guard let connections, let message = encodeMessage(outcomingMessage) else {
            // send error
            return
        }
        for connection in connections {
            connection.socket.send(message)
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
                    // send error: no kickPlayerID
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
                    // send error: no changingTilesIndexes
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
                    // send error: no direction or letters
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
                    // send error: no reaction or it is invalid
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
            // send error
            return
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
                // send error: socket is already connected
                return
            }
            guard let userName = try await User.find(userID, on: db)?.username else {
                // send error: could not fetch username from db
                return
            }
            guard let room = try await Room.query(on: db).with(\.$players).filter(\.$id == roomID).first() else {
                // send error: cannot fetch room
                return
            }
            let isUserInRoom = room.players.contains { $0.$player.id == userID }
            guard isUserInRoom else {
                // send error: user is not a valid player in this room
                return
            }
            // TODO: check valid roomID
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
        } catch {
            // send error
        }
    }
    
    private func handleChangeRoomPrivacy(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
                // send error: not admin
                return
            }
            guard room.gameStatus == GameStatus.ready.rawValue ||
                    room.gameStatus == GameStatus.waiting.rawValue
            else {
                // send error: game already started
                return
            }
            room.isPrivate.toggle()
            try await room.update(on: db)
            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(event: .roomChangedPrivacy, newRoomPrivacy: room.isPrivate)
            )
        } catch {
            // send error
        }
    }
    
    private func handleKickPlayer(
        socket: WebSocket,
        roomID: UUID,
        kickPlayerID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
                // send error: not admin
                return
            }
            guard room.gameStatus == GameStatus.waiting.rawValue || room.gameStatus == GameStatus.ready.rawValue else {
                // send error: cannot kick player because game status is invalid
                return
            }
            guard kickPlayerID != userID else {
                // send error: admin cannot kick themselves
                return
            }
            guard connections[roomID]?.contains(where: { $0.userID == kickPlayerID }) == true else {
                // send error: player to kick is not part of the room
                return
            }
            
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
            
            if room.gameStatus != initialGameStatus, let adminConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [adminConnection],
                    outcomingMessage: OutcomingMessage(event: .roomWaiting)
                )
            }
        } catch {
            // send error
        }
    }
    
    private func handleLeaveRoom(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.first(where: { $0.socket === socket })?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.query(on: db).with(\.$players).filter(\.$id == roomID).first() else {
                // send error: room not found
                return
            }
            guard room.gameStatus == GameStatus.waiting.rawValue || room.gameStatus == GameStatus.ready.rawValue else {
                // send error: cannot leave room because game status is invalid
                return
            }
            
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
                
                if room.gameStatus != initialGameStatus, let adminConnection = connections[roomID]?.first(where: { $0.userID == room.$admin.id }) {
                    sendMessage(
                        to: [adminConnection],
                        outcomingMessage: OutcomingMessage(event: .roomWaiting)
                    )
                }
            }
        } catch {
            // send error
        }
    }
    
    private func handleExchangeTiles(
        socket: WebSocket,
        roomID: UUID,
        changingTiles: [Int],
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db) else {
                // send error: only the admin can close the room
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue else {
                // send error: exchange turn is availible only for ongoing game
                return
            }
            guard room.turnOrder[room.currentTurnIndex] == userID else {
                // send error: it is another player's turn
                return
            }
            guard room.tilesLeft.values.reduce(0, +) >= 7 else {
                // send error: there must be 7 or more tiles left
                return
            }
            guard changingTiles.count > 0 && changingTiles.count < 8 else {
                // send error: you can exchange from 1 to 7 tiles
                return
            }
            
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
        } catch {
            // send error
        }
    }
    
    private func handleEndGameSuggestion(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db) else {
                // send error: only the admin can close the room
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue else {
                // send error: ending turn is availible only for ongoing game
                return
            }
            guard room.turnOrder[room.currentTurnIndex] == userID else {
                // send error: it is another player's turn
                return
            }
            guard room.currentSkippedTurns >= 6 else {
                // send error: game can't be ended yet
                return
            }
            
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
        } catch {
            // send error
        }
    }
    
    private func handleEndTurn(
        socket: WebSocket,
        roomID: UUID,
        emptyTurn: Bool,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db) else {
                // send error: only the admin can close the room
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue else {
                // send error: ending turn is availible only for ongoing game
                return
            }
            guard room.turnOrder[room.currentTurnIndex] == userID else {
                // send error: it is another player's turn
                return
            }
            if emptyTurn {
                room.currentSkippedTurns += 1
            } else {
                room.currentSkippedTurns = 0
            }
            try await room.update(on: db)
            guard let playerTiles = room.playersTiles[userID.uuidString] else {
                // send error
                return
            }
            
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
        } catch {
            // send error
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
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db) else {
                // send error: only the admin can close the room
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue else {
                // send error: placing the word is availible only for ongoing game
                return
            }
            guard room.turnOrder[room.currentTurnIndex] == userID else {
                // send error: it is another player's turn
                return
            }
            guard var playerTiles = room.playersTiles[userID.uuidString] else {
                // send error
                return
            }
            let gameService = WordGameService()
            let word = letters.buildWord(with: playerTiles, direction: direction)
            guard try await gameService.isValidWord(word, on: db) else {
                // send error: word \(word) is invalid
                return
            }
            if room.placedWords.count == 0 {
                guard letters.contains(where: { $0.position == [7, 7] }) else {
                    // send error: first word on the board must cover the center [7; 7]
                    return
                }
            }
            
            var board = room.board
            
            // Checking words around new word
            let _ = gameService.findAllWords(
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
                    // send error: new word should cross any other word on the board
                    return
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
        } catch {
            // send error
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
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
                // send error: not admin
                return
            }
            guard room.gameStatus == GameStatus.ready.rawValue ||
            room.gameStatus == GameStatus.waiting.rawValue else {
                // send error: cannot start because game status is invalid
                return
            }
            
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
            try await room.save(on: db)
            
            for playerID in turnOrder {
                let playerTiles = playersTiles[playerID.uuidString]
                
                let message = OutcomingMessage(
                    event: .gameStarted,
                    boardLayout: boardLayout,
                    currentTurn: turnOrder[room.currentTurnIndex],
                    playerTiles: playerTiles
                )
                
                guard let currentConnection = connections[roomID]?.first(where: { $0.userID == playerID }) else {
                    // something went wrong
                    return
                }
                sendMessage(to: [currentConnection], outcomingMessage: message)
            }
        } catch {
            // send error
        }
    }
    
    private func handlePauseGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
                // send error: only the admin can pause the game
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue else {
                // send error: cannot pause because game status is invalid
                return
            }
            room.gameStatus = GameStatus.paused.rawValue
            try await room.update(on: db)
            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(event: .gamePaused)
            )
        } catch {
            // send error
        }
    }
    
    private func handleResumeGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id == userID else {
                // send error: only the admin can resume the game
                return
            }
            guard room.gameStatus == GameStatus.paused.rawValue else {
                // send error: cannot resume because game status is invalid
                return
            }
            room.gameStatus = GameStatus.started.rawValue
            try await room.update(on: db)
            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(
                    event: .gameResumed,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )
            )
        } catch {
            // send error
        }
    }
    
    private func handleSendReaction(
        socket: WebSocket,
        roomID: UUID,
        reaction: String,
        db: Database
    ) async {
        guard isSocketConnected(to: roomID, socket: socket) else {
            // send error: no connections / current connection isn't connected to room
            return
        }
        guard let userID = connections[roomID]?.first(where: { $0.socket === socket })?.userID else {
            // send error: user not found for this connection
            return
        }
        
        sendMessage(
            to: connections[roomID],
            outcomingMessage: OutcomingMessage(
                event: .reactionSent,
                reaction: reaction,
                senderID: userID
            )
        )
    }
    
    private func handleLeaveGame(
        socket: WebSocket,
        roomID: UUID,
        db: Database
    ) async {
        do {
            guard isSocketConnected(to: roomID, socket: socket) else {
                // send error: no connections / current connection isn't connected to room
                return
            }
            guard let userID = connections[roomID]?.first(where: { $0.socket === socket })?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.query(on: db).with(\.$players).with(\.$admin).filter(\.$id == roomID).first() else {
                return
            }
            guard room.gameStatus == GameStatus.started.rawValue || room.gameStatus == GameStatus.paused.rawValue else {
                // send error: cannot leave because game status is invalid
                return
            }
            
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
                try await resetRoomState(for: room, db: db)
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
        } catch {
            // send error
        }
    }
}

extension WebSocketManager {
    
    private func addConnection(roomID: UUID, userID: UUID, socket: WebSocket) -> UserConnection {
        let newConnection = UserConnection(userID: userID, socket: socket)
        connections[roomID, default: []].append(newConnection)
        return newConnection
    }
    
    private func isSocketConnected(to roomID: UUID, socket: WebSocket) -> Bool {
        guard let connections = connections[roomID] else {
            return false
        }
        return connections.contains { $0.socket === socket }
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
  
    private func resetRoomState(for room: Room, db: Database) async throws {
        room.gameStatus = GameStatus.waiting.rawValue
        room.leaderboard = [:]
        room.tilesLeft = [:]
        room.board = ""
        room.turnOrder = []
        room.currentTurnIndex = 0
        room.playersTiles = [:]
        room.placedWords = []
        try await room.update(on: db)
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
            print("Error encoding message: \(error)")
            return nil
        }
    }
}
