import Vapor

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
        guard let tokenValue = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing or invalid token.")
        }
        
        guard let token = try await Token.query(on: req.db)
            .filter("value", .equal, tokenValue)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid or expired token.")
        }
        
        let user = try req.content.decode(UpdateUserDTO.self)
        let userID = token.$user.id
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
