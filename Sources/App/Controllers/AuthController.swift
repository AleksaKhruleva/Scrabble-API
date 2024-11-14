import Vapor

struct AuthController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("api", "v1", "auth")
        
        // MARK: - Register route
        // Usage:
        /// Route: POST {base-url}/api/v1/auth/register
        /// Body: { username, email, password }
        // Response:
        /// { user }
        users.post("register", use: register)
        
        // MARK: - Middleware
        let basicAuthMiddleware = User.authenticator()
        let basicAuthGroup = users.grouped(basicAuthMiddleware)
        
        // MARK: - Login route
        // Usage:
        /// Route: POST  {base-url}/api/v1/auth/login
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
        basicAuthGroup.post("login", use: login)
    }
    
    @Sendable
    func register(_ req: Request) async throws -> User.Public {
        let registringUser = try req.content.decode(RegisterUserDTO.self)
        
        let user = User(
            username: registringUser.username,
            email: registringUser.email,
            password: registringUser.password
        )
        user.password = try Bcrypt.hash(user.password)
        
        try await user.save(on: req.db)
        return user.convertToPublic()
    }
    
    @Sendable
    func login(_ req: Request) async throws -> Token {
        let user = try req.auth.require(User.self)
        let token = try Token.generate(for: user)
        
        try await token.save(on: req.db)
        return token
    }
}
