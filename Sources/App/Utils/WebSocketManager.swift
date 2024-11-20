import Vapor
import FluentKit

final class WebSocketManager: @unchecked Sendable {
    
    static let shared = WebSocketManager()
    private var connections: [UUID: [UserConnection]] = [:]
    
    private init() {}
    
    func removeConnection(for socket: WebSocket, roomID: UUID? = nil) {
        if let roomID {
            connections[roomID]?.removeAll { $0.socket === socket }
        } else {
            for roomID in connections.keys {
                connections[roomID]?.removeAll { $0.socket === socket }
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
            case .closeRoom:
                await handleCloseRoom(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    db: req.db
                )
            case .skipTurn:
                await handleSkipTurn(
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
            case .makeMove:
                guard
                    let direction = incomingMessage.direction,
                    let letters = incomingMessage.letters else {
                    // send error: no direction or letters
                    return
                }
                await handleMakeMove(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    direction: direction,
                    letters: letters,
                    db: req.db
                )
            case .startGame:
                await handleStartGame(
                    socket: socket,
                    roomID: incomingMessage.roomID,
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
            try await RoomPlayer.query(on: db)
                .filter(\RoomPlayer.$room.$id == roomID)
                .filter(\RoomPlayer.$player.$id == kickPlayerID)
                .delete()
            
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
            guard let userID = connections[roomID]?.filter({ $0.socket === socket }).first?.userID else {
                // send error: user not found for this connection
                return
            }
            guard let room = try await Room.find(roomID, on: db), room.$admin.id != userID else {
                // send error: admin cannot leave the room
                return
            }
            guard room.gameStatus == GameStatus.waiting.rawValue || room.gameStatus == GameStatus.ready.rawValue else {
                // send error: cannot leave room because game status is invalid
                return
            }
            
            try await db.transaction { db in
                try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .filter(\.$player.$id == userID)
                    .delete()
                
                let playerCount = try await RoomPlayer.query(on: db)
                    .filter(\.$room.$id == roomID)
                    .count()
                
                if room.gameStatus == GameStatus.ready.rawValue && playerCount < room.maxPlayers {
                    room.gameStatus = GameStatus.waiting.rawValue
                    try await room.update(on: db)
                }
            }
            
            if let leavingPlayerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [leavingPlayerConnection],
                    outcomingMessage: OutcomingMessage(event: .leftRoom)
                )
                try await leavingPlayerConnection.socket.close()
                removeConnection(for: leavingPlayerConnection.socket, roomID: roomID)
                sendMessage(
                    to: connections[roomID],
                    outcomingMessage: OutcomingMessage(
                        event: .playerLeft,
                        leftPlayerID: userID
                    )
                )
            }
        } catch {
            // send error
        }
    }
    
    private func handleCloseRoom(
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
                // send error: only the admin can close the room
                return
            }
            guard room.gameStatus == GameStatus.waiting.rawValue || room.gameStatus == GameStatus.ready.rawValue else {
                // send error: cannot close room because game status is invalid
                return
            }
            
            try await room.delete(on: db)
            
            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(event: .roomClosed)
            )
            
            if let roomConnections = connections[roomID] {
                for connection in roomConnections {
                    try await connection.socket.close()
                }
            }
            
            connections[roomID] = nil
        } catch {
            // send error
        }
    }
    
    private func handleSkipTurn(
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
                // send error: skip turn is availible only for ongoing game
                return
            }
            guard room.turnOrder[room.currentTurnIndex] == userID else {
                // send error: it is another player's turn
                return
            }
            if let skippingPlayerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                room.currentTurnIndex = (room.currentTurnIndex + 1) % room.turnOrder.count
                try await room.update(on: db)
                sendMessage(
                    to: [skippingPlayerConnection],
                    outcomingMessage: OutcomingMessage(
                        event: .skippedTurn,
                        currentTurn: room.turnOrder[room.currentTurnIndex]
                    )
                )
                let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
                sendMessage(
                    to: otherConnections,
                    outcomingMessage: OutcomingMessage(
                        event: .playerSkippedTurn,
                        skippedPlayerID: userID,
                        currentTurn: room.turnOrder[room.currentTurnIndex]
                    )
                )
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
                // send error: skip turn is availible only for ongoing game
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
    
    private func handleMakeMove(
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
                // send error: skip turn is availible only for ongoing game
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
            let word = letters.buildWord(with: playerTiles, direction: direction)
            guard isValidWord(word) else {
                // send error: word is invalid
                return
            }
            if room.placedWords.count == 0 {
                guard letters.contains(where: { $0.position == [7, 7] }) else {
                    // send error: first word on the board must cover the center [7; 7]
                    return
                }
            }
            
            // check words around new word
            
            // place the word on the board
            var board = room.board
            for letter in letters {
                let row = letter.position[0]
                let col = letter.position[1]
                let index = row * 15 + col
                board = board.replacingCharacters(
                    in: board.index(
                        board.startIndex,
                        offsetBy: index
                    )...board.index(
                        board.startIndex,
                        offsetBy: index
                    ),
                    with: playerTiles[letter.tileIndex]
                )
            }
            
            // giving new tiles to player
            var tilesLeft = room.tilesLeft
            playerTiles = redistributeTiles(
                to: userID,
                withTiles: playerTiles,
                onIndexes: letters.getIndexes(),
                using: &tilesLeft
            )
            
            // count points, update leaderboard
            let playerScore = calculateScore(
                letters: letters,
                board: board,
                boardLayout: BoardLayoutProvider.shared.layout,
                tileWeights: LettersInfoProvider.shared.initialWeights()
            )
            
            // update room
            room.playersTiles[userID.uuidString] = playerTiles
            room.currentTurnIndex = (room.currentTurnIndex + 1) % room.turnOrder.count
            room.tilesLeft = tilesLeft
            room.placedWords.append(word)
            room.board = board
            // update leaderboard, etc ...
            try await room.update(on: db)
            
            // notice player about his points for thiw word
            if let playerConnection = connections[roomID]?.first(where: { $0.userID == userID }) {
                sendMessage(
                    to: [playerConnection],
                    outcomingMessage: OutcomingMessage(
                        event: .madeMove,
                        newWord: word,
                        scoredPoints: playerScore,
                        currentTurn: room.turnOrder[room.currentTurnIndex],
                        playerTiles: playerTiles
                    )
                )
            }
            
            // notice other players about the turn
            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .playerMadeMove,
                    madeMovePlayerID: userID,
                    newWord: word,
                    currentTurn: room.turnOrder[room.currentTurnIndex]
                )
            )
        } catch {
            // send error
        }
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
            guard room.gameStatus == GameStatus.ready.rawValue else {
                // send error: cannot start because game status is invalid
                return
            }
            
            let boardSize = BoardLayoutProvider.shared.size
            let boardLayout = BoardLayoutProvider.shared.layout
            let boardString = String(repeating: ".", count: boardSize * boardSize)
            
            let roomPlayers = try await room.$players.query(on: db).with(\.$player).all()
            let roomPlayersMap = Dictionary(uniqueKeysWithValues: roomPlayers.map { ($0.$player.id, $0) })
            
            let turnOrder = roomPlayersMap.keys.shuffled()
            
            var leaderboard: [String: Int] = [:]
            for playerID in turnOrder {
                if let roomPlayer = roomPlayersMap[playerID] {
                    leaderboard[roomPlayer.player.username] = 0
                }
            }
            
            var tilesLeft = LettersInfoProvider.shared.initialQuantities()
            let playersTiles = distributeTiles(to: turnOrder, using: &tilesLeft)
            
            let leaderboardCopy = leaderboard
            let tilesLeftCopy = tilesLeft
            
            room.board = boardString
            room.turnOrder = turnOrder
            room.leaderboard = leaderboardCopy
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
                    leaderboard: leaderboardCopy,
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
}

// Need to be moved to some WordManager class
extension WebSocketManager {
    
    func calculateScore(
        letters: [LetterPlacement],
        board: String,
        boardLayout: [[BonusType]],
        tileWeights: [String: Int]
    ) -> Int {
        var totalScore = 0
        var wordMultiplier = 1

        for letterPlacement in letters {
            let row = letterPlacement.position[0]
            let col = letterPlacement.position[1]
            let index = row * 15 + col

            let letter = board[board.index(board.startIndex, offsetBy: index)]

            guard let letterScore = tileWeights[String(letter)] else {
                continue
            }

            let bonus = boardLayout[row][col]

            switch bonus {
            case .doubleLetter:
                totalScore += letterScore * 2
            case .tripleLetter:
                totalScore += letterScore * 3
            case .doubleWord:
                totalScore += letterScore
                wordMultiplier *= 2
            case .tripleWord:
                totalScore += letterScore
                wordMultiplier *= 3
            case .none:
                totalScore += letterScore
            }
        }

        return totalScore * wordMultiplier
    }

    private func findAllWords(
        from letters: [LetterPlacement],
        with playerTiles: [String],
        direction: Direction,
        board: [[String]]
    ) -> [String] {
        var words = [String]()

        // Основное слово
        let mainWord = letters.buildWord(with: playerTiles, direction: direction)
        words.append(mainWord)

        // Проверяем пересечения
        for letter in letters {
            let row = letter.position[0]
            let col = letter.position[1]
            if direction == Direction.horizontal {
                // Проверяем вертикальное слово
                let verticalWord = findWord(row: row, col: col, direction: Direction.vertical, board: board)
                if verticalWord.count > 1 {
                    words.append(verticalWord)
                }
            } else {
                // Проверяем горизонтальное слово
                let horizontalWord = findWord(row: row, col: col, direction: Direction.horizontal, board: board)
                if horizontalWord.count > 1 {
                    words.append(horizontalWord)
                }
            }
        }

        return words
    }

    private func findWord(row: Int, col: Int, direction: Direction, board: [[String]]) -> String {
        var word = ""
        var r = row
        var c = col

        // Идём назад, чтобы найти начало слова
        while r >= 0, c >= 0, board[r][c] != ".", board[r][c] != " " {
            if direction == Direction.horizontal {
                c -= 1
            } else {
                r -= 1
            }
        }

        // Идём вперёд, чтобы собрать слово
        if direction == Direction.horizontal {
            c += 1
        } else {
            r += 1
        }

        while r < 15, c < 15, board[r][c] != ".", board[r][c] != " " {
            word.append(board[r][c])
            if direction == Direction.horizontal {
                c += 1
            } else {
                r += 1
            }
        }

        return word
    }
    
    private func validateWords(_ words: [String]) throws {
       for word in words {
           guard isValidWord(word) else {
               throw Abort(.badRequest, reason: "Invalid word: \(word)")
           }
       }
   }

   private func isValidWord(_ word: String) -> Bool {
       // самая наикрутейшая возможная и доступная человечеству проверка валидности слова
       return true
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
        
        for index in changingTiles {
            guard let randomLetter = tiles.keys.randomElement() else { break }
            newPlayerTiles[index] = randomLetter
            if let count = tiles[randomLetter], count > 1 {
                tiles[randomLetter] = count - 1
            } else {
                tiles.removeValue(forKey: randomLetter)
            }
        }
        
        return newPlayerTiles
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
