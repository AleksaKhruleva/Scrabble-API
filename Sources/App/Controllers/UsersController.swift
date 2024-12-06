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
}
// swiftlint:enable orphaned_doc_comment
