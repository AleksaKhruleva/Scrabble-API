import Vapor

struct UsersController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("api", "v1", "users")
        
        // MARK: - Non-protected routes
        users.get(use: index)
        users.post(use: create)
        
        // MARK: - Middleware
        let basicAuthMiddleware = User.authenticator()
        let basicAuthGroup = users.grouped(basicAuthMiddleware)
        
        // MARK: - Protected routes
        // Usage:
        /// Route: {base-url}/api/v1/users/login
        /// Body: {} empty
        /// AuthType -> Basic Auth ->
        ///   username: {email}
        ///   password: {password}
        // Response:
        /// "id": {request-id},
        ///     "user": {
        ///         "id": {user-id}
        ///     },
        /// "value": {token-value}
        basicAuthGroup.post("login", use: loginHandler)
    }
    
    @Sendable
    func index(req: Request) async throws -> [User.Public] {
        let users = try await User.query(on: req.db).all()
        
        return users.map { $0.convertToPublic() }
    }
    
    @Sendable
    func create(_ req: Request) async throws -> User.Public {
        let user = try req.content.decode(User.self)
        user.password = try Bcrypt.hash(user.password)
        
        try await user.save(on: req.db)
        return user.convertToPublic()
    }
    
    @Sendable
    func loginHandler(_ req: Request) async throws -> Token {
        let user = try req.auth.require(User.self)
        let token = try Token.generate(for: user)
        
        try await token.save(on: req.db)
        return token
    }
}
