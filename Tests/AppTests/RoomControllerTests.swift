@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("RoomController Tests", .serialized)
struct RoomControllerTests {
    
    let apiService = APIKeyService()
    
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            app.logger.logLevel = .error
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    @Test("Create Room")
    func test_createRoom_withValidData_shouldCreateRoom() async throws {
        let admin = User(username: "admin", email: "admin@example.com", password: try Bcrypt.hash("password"))
        
        try await withApp { app in
            try await admin.save(on: app.db)
            
            let token = try Token.generate(for: admin)
            try await token.save(on: app.db)
            
            let createRoomDTO = CreateRoomDTO(isPrivate: true, timePerTurn: 0, maxPlayers: 2)
            
            try await app.test(.POST, "rooms/create", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(createRoomDTO)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                
                let room = try res.content.decode(RoomDTO.self)
                XCTAssertEqual(room.isPrivate, true)
            })
        }
    }
    
    @Test("Create Room with same admin")
    func test_createRoom_withSameAdmin_shouldReturnConflict() async throws {
        let admin = User(username: "admin", email: "admin@example.com", password: try Bcrypt.hash("password"))
        
        try await withApp { app in
            try await admin.save(on: app.db)
            
            let token = try Token.generate(for: admin)
            try await token.save(on: app.db)
            
            let room = Room(
                inviteCode: "111111",
                isPrivate: false,
                adminID: try admin.requireID(),
                timePerTurn: 0,
                maxPlayers: 2
            )
            try await room.save(on: app.db)
            
            let createRoomDTO = CreateRoomDTO(isPrivate: true, timePerTurn: 0, maxPlayers: 2)
            
            try await app.test(.POST, "rooms/create", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(createRoomDTO)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
                
                let errorResponse = try res.content.decode(ErrorDTO.self)
                #expect(errorResponse.reason.contains("Another room with this admin already exists"))
            })
        }
    }
    
    @Test("Join Random Public Room")
    func test_joinRandomPublicRoom_withAvailableRooms_shouldJoin() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))
        let admin = User(username: "admin", email: "admin@example.com", password: try Bcrypt.hash("password"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            try await admin.save(on: app.db)
            
            let room = Room(
                inviteCode: "111111",
                isPrivate: false,
                adminID: try admin.requireID(),
                timePerTurn: 0,
                maxPlayers: 2
            )
            try await room.save(on: app.db)
            
            let token = try Token.generate(for: user)
            try await token.save(on: app.db)
            
            try await app.test(.POST, "rooms/joinRandomPublic", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(JoinRoomDTO(inviteCode: "111111"))
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                
                let roomDTO = try res.content.decode(RoomDTO.self)
                XCTAssertEqual(roomDTO.inviteCode, "111111")
            })
        }
    }
    
    @Test("Join Random Public Room with no Public Rooms")
    func test_joinRandomPublicRoom_withNoAvailableRooms_shouldReturnNotFound() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))
        let admin = User(username: "admin", email: "admin@example.com", password: try Bcrypt.hash("password"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            try await admin.save(on: app.db)
            
            let room = Room(
                inviteCode: "111111",
                isPrivate: true,
                adminID: try admin.requireID(),
                timePerTurn: 0,
                maxPlayers: 2
            )
            try await room.save(on: app.db)
            
            let token = try Token.generate(for: user)
            try await token.save(on: app.db)
            
            try await app.test(.POST, "rooms/joinRandomPublic", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(JoinRoomDTO(inviteCode: "111111"))
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
                
                let errorResponse = try res.content.decode(ErrorDTO.self)
                #expect(errorResponse.reason.contains("No open rooms available at the moment"))
            })
        }
    }
    
    @Test("Join Random Public Room with no Rooms")
    func test_joinRandomPublicRoom_withNoRooms_shouldReturnNotFound() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            
            let token = try Token.generate(for: user)
            try await token.save(on: app.db)
            
            try await app.test(.POST, "rooms/joinRandomPublic", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(JoinRoomDTO(inviteCode: "111111"))
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    @Test("Join Room by Invite Code")
    func test_joinByInviteCode_withValidCode_shouldJoinRoom() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))
        let admin = User(username: "admin", email: "admin@example.com", password: try Bcrypt.hash("password"))

        try await withApp { app in
            try await user.save(on: app.db)
            try await admin.save(on: app.db)

            let room = Room(
                inviteCode: "111111",
                isPrivate: true,
                adminID: try admin.requireID(),
                timePerTurn: 0,
                maxPlayers: 2
            )
            try await room.save(on: app.db)

            let token = try Token.generate(for: user)
            try await token.save(on: app.db)

            let joinRoomDTO = JoinRoomDTO(inviteCode: "111111")

            try await app.test(.POST, "rooms/joinByInviteCode", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(joinRoomDTO)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let roomDTO = try res.content.decode(RoomDTO.self)
                XCTAssertEqual(roomDTO.inviteCode, "111111")
            })
        }
    }
    
    @Test("Join Room by Invite Code with invalid Code")
    func test_joinByInviteCode_withInvalidCode_shouldReturnNotFound() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))

        try await withApp { app in
            try await user.save(on: app.db)

            let token = try Token.generate(for: user)
            try await token.save(on: app.db)

            let joinRoomDTO = JoinRoomDTO(inviteCode: "222222")

            try await app.test(.POST, "rooms/joinByInviteCode", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(joinRoomDTO)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
                
                let errorResponse = try res.content.decode(ErrorDTO.self)
                #expect(errorResponse.reason.contains(
                    "Room with the given invite code not found or the game has already started"
                ))
            })
        }
    }
    
    @Test("Join Room by Invite Code with no Code")
    func test_joinByInviteCode_withNoCode_shouldReturnBadRequest() async throws {
        let user = User(username: "player", email: "player@example.com", password: try Bcrypt.hash("password"))

        try await withApp { app in
            try await user.save(on: app.db)

            let token = try Token.generate(for: user)
            try await token.save(on: app.db)

            let joinRoomDTO = JoinRoomDTO(inviteCode: nil)

            try await app.test(.POST, "rooms/joinByInviteCode", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.value)
                try req.content.encode(joinRoomDTO)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                
                let errorResponse = try res.content.decode(ErrorDTO.self)
                #expect(errorResponse.reason.contains("Invite code is required"))
            })
        }
    }
}
