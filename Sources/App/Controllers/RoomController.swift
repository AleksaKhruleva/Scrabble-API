import Fluent
import Vapor

struct RoomController: RouteCollection {

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let rooms = routes.grouped("rooms")

        // MARK: - Middleware
        let tokenAuthMiddleware = Token.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthGroup = rooms.grouped(tokenAuthMiddleware, guardAuthMiddleware)

        tokenAuthGroup.post("create", use: create)
        tokenAuthGroup.post("joinRandomPublic", use: joinRandomPublic)
        tokenAuthGroup.post("joinByInviteCode", use: joinByInviteCode)
        tokenAuthGroup.get("getPublic", use: getPublicRooms)
    }

    @Sendable
    func create(req: Request) async throws -> RoomDTO {
        let createRoomDTO = try req.content.decode(CreateRoomDTO.self)

        let userService = UserService(db: req.db)
        let adminID = try await userService.fetchUserID(req: req)
        let room = try await createRoom(on: req.db, createRoomDTO: createRoomDTO, adminID: adminID)
        return room.toDTO(for: adminID)
    }

    @Sendable
    func joinRandomPublic(req: Request) async throws -> RoomDTO {
        let joinRoomDTO = try req.content.decode(JoinRoomDTO.self)

        let userService = UserService(db: req.db)
        let userID = try await userService.fetchUserID(req: req)
        guard let room = try await joinRandomPublicRoom(on: req.db, joinRoomDTO: joinRoomDTO, userID: userID) else {
            // Impossible to get here
            throw Abort(.internalServerError, reason: "An error occurred while joining the room")
        }
        return room.toDTO(for: userID)
    }

    @Sendable
    func joinByInviteCode(req: Request) async throws -> RoomDTO {
        let joinRoomDTO = try req.content.decode(JoinRoomDTO.self)

        let userService = UserService(db: req.db)
        let userID = try await userService.fetchUserID(req: req)
        guard let room = try await joinRoomByInviteCode(on: req.db, joinRoomDTO: joinRoomDTO, userID: userID) else {
            // Impossible to get here
            throw Abort(.internalServerError, reason: "An error occurred while joining the room")
        }
        return room.toDTO(for: userID)
    }
    
    @Sendable
    func getPublicRooms(req: Request) async throws -> [RoomListElementDTO] {
        let rooms = try await Room.query(on: req.db)
            .filter("is_private", .equal, false)
            .all()
        
        return rooms.map { $0.toListElementDTO() }
    }
}

// MARK: - Private

extension RoomController {

    private func createRoom(on db: Database, createRoomDTO: CreateRoomDTO, adminID: UUID) async throws -> Room {
        return try await db.transaction { db in
            var room: Room
            while true {
                do {
                    guard try await User.find(adminID, on: db) != nil else {
                        throw Abort(.badRequest, reason: "User with ID \(adminID) does not exist")
                    }
                    if try await Room.query(on: db).filter(\.$admin.$id == adminID).first() != nil {
                        throw Abort(.conflict, reason: "Another room with this admin already exists")
                    }
                } catch {
                    throw ErrorService.shared.handleError(error)
                }
                let inviteCode = String(UUID().uuidString.prefix(6).uppercased())
                room = Room(
                    inviteCode: inviteCode,
                    isPrivate: createRoomDTO.isPrivate,
                    adminID: adminID,
                    timePerTurn: createRoomDTO.timePerTurn,
                    maxPlayers: createRoomDTO.maxPlayers
                )
                do {
                    try await room.save(on: db)
                    try await createRoomPlayer(on: db, roomID: try room.requireID(), playerID: adminID)
                    room = try await getRoomWithPlayers(on: db, room: room)
                    break
                } catch let error as DatabaseError where error.isConstraintFailure {
                    continue
                } catch {
                    throw ErrorService.shared.handleError(error)
                }
            }
            return room
        }
    }

    private func joinRandomPublicRoom(on db: Database, joinRoomDTO: JoinRoomDTO, userID: UUID) async throws -> Room? {
        return try await db.transaction { db in
            do {
                guard let randomRoom = try await Room.query(on: db)
                    .filter(\.$isPrivate == false)
                    .filter(\.$gameStatus == GameStatus.waiting.rawValue)
                    .all()
                    .randomElement()
                else {
                    throw Abort(.notFound, reason: "No open rooms available at the moment")
                }
                return try await joinRoom(randomRoom, with: userID, on: db)
            } catch {
                throw ErrorService.shared.handleError(error)
            }
        }
    }

    private func joinRoomByInviteCode(on db: Database, joinRoomDTO: JoinRoomDTO, userID: UUID) async throws -> Room? {
        guard let inviteCode = joinRoomDTO.inviteCode else {
            throw Abort(.badRequest, reason: "Invite code is required")
        }
        return try await db.transaction { db in
            do {
                guard let specificRoom = try await Room.query(on: db)
                    .filter(\.$inviteCode == inviteCode)
                    .filter(\.$gameStatus == GameStatus.waiting.rawValue)
                    .first()
                else {
                    throw Abort(
                        .notFound,
                        reason: "Room with the given invite code not found or the game has already started"
                    )
                }
                return try await joinRoom(specificRoom, with: userID, on: db)
            } catch {
                throw ErrorService.shared.handleError(error)
            }
        }
    }
}

extension RoomController {

    private func createRoomPlayer(on db: Database, roomID: UUID, playerID: UUID) async throws {
        let roomPlayer = RoomPlayer(
            roomID: roomID,
            playerID: playerID
        )
        try await roomPlayer.save(on: db)
    }

    private func getRoomWithPlayers(on db: Database, room: Room) async throws -> Room {
        let roomWithPlayers = try await Room.query(on: db)
            .with(\.$players) { $0.with(\.$player) }
            .filter(\.$inviteCode == room.inviteCode)
            .first()
        guard let roomWithPlayers else {
            throw Abort(.notFound, reason: "Room not found")
        }
        return roomWithPlayers
    }

    private func joinRoom(_ room: Room, with playerID: UUID, on db: Database) async throws -> Room {
        guard try await Room
            .find(room.id, on: db)?.gameStatus == GameStatus.waiting.rawValue
        else {
            throw Abort(.conflict, reason: "Room status has changed. Please try joining again")
        }
        try await createRoomPlayer(
            on: db,
            roomID: try room.requireID(),
            playerID: playerID
        )
        let updatedRoom = try await getRoomWithPlayers(on: db, room: room)
        if updatedRoom.players.count == updatedRoom.maxPlayers {
            updatedRoom.gameStatus = GameStatus.ready.rawValue
            try await updatedRoom.update(on: db)
        }
        return updatedRoom
    }
}
