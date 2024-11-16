import Vapor
import FluentKit

final class WebSocketManager: @unchecked Sendable {
    
    static let shared = WebSocketManager()
    private var connections: [UUID: [Connection]] = [:]
    
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
    
    // Сделать ли отдельный метод для отправки ошибки ???
    
    func sendMessage(to connections: [Connection]?, outcomingMessage: OutcomingMessage) {
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
        let userService = UserService(db: req.db)
        do {
            switch incomingMessage.action {
            case .joinRoom:
                let userID = try await userService.fetchUserID(req: req)
                await handleJoinRoom(
                    socket: socket,
                    roomID: incomingMessage.roomID,
                    userID: userID,
                    db: req.db
                )
            case .makeRoomPrivate:
                await handleMakeRoomPrivate(
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
            let connection = addConnection(roomID: roomID, userID: userID, socket: socket)
            sendMessage(to: [connection], outcomingMessage: OutcomingMessage(event: .joinedRoom))
            let otherConnections = connections[roomID]?.filter({ $0.socket !== socket })
            sendMessage(
                to: otherConnections,
                outcomingMessage: OutcomingMessage(
                    event: .newPlayerJoined,
                    newPlayerInfo: PlayerInfo(id: userID, name: userName)
                )
            )
        } catch {
            // send error
        }
    }
    
    private func handleMakeRoomPrivate(
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
            room.isPrivate = true
            try await room.update(on: db)
            sendMessage(
                to: connections[roomID],
                outcomingMessage: OutcomingMessage(event: .roomWasMadePrivate)
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
                        event: .playerWasKicked,
                        kickedPlayerID: kickPlayerID
                    )
                )
            }
        } catch {
            // send error
        }
    }
}


extension WebSocketManager {
    
    private func addConnection(roomID: UUID, userID: UUID, socket: WebSocket) -> Connection {
        let newConnection = Connection(userID: userID, socket: socket)
        connections[roomID, default: []].append(newConnection)
        return newConnection
    }
    
    private func isSocketConnected(to roomID: UUID, socket: WebSocket) -> Bool {
        guard let connections = connections[roomID] else {
            return false
        }
        return connections.contains { $0.socket === socket }
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
