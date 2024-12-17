import Vapor
// swiftlint:disable orphaned_doc_comment
struct UsersController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("api", "v1", "users")

        // MARK: - Non-protected routes
        users.get(use: index)

        // MARK: - Middleware
        let tokenAuthMiddleware = Token.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthGroup = users.grouped(tokenAuthMiddleware, guardAuthMiddleware)

        // MARK: - Protected routes
        // Usage:
        /// Route: PUT {base-url}/api/v1/users
        /// AuthType -> Bearer Token -> Token: {token-value}
        /// Body -> { username?, email?, password? }
        // Response:
        /// { user }
        tokenAuthGroup.put(use: update)
        tokenAuthGroup.post("delete", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [User.Public] {
        let users = try await User.query(on: req.db).all()

        return users.map { $0.convertToPublic() }
    }

    @Sendable
    func update(req: Request) async throws -> User.Public {
        let user = try req.content.decode(UpdateUserDTO.self)

        let userService = UserService(db: req.db)
        let userID = try await userService.fetchUserID(req: req)

        guard let updatedUser = try await User.find(userID, on: req.db) else {
            throw Abort(.badRequest, reason: "User not found")
        }

        if let username = user.username {
            updatedUser.username = username
        }
        if let email = user.email {
            updatedUser.email = email
        }
        if let password = user.password {
            updatedUser.password = try Bcrypt.hash(password)
        }

        try await updatedUser.update(on: req.db)
        return updatedUser.convertToPublic()
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let userService = UserService(db: req.db)
        let userID = try await userService.fetchUserID(req: req)
        
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }
        
        do {
            try await req.db.transaction { db in
                try await user.delete(on: db)
                
                try await Token.query(on: db)
                    .filter("user_id", .equal, userID)
                    .delete()
            }
        } catch {
            throw ErrorService.shared.handleError(error)
        }
        
        return .ok
    }
}
// swiftlint:enable orphaned_doc_comment
