import Vapor
import Fluent

struct UseAuthController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let uses = routes.grouped("api", "v1", "test")
                
        // MARK: - Non-protected routes
        uses.get(use: index)
        uses.get(":id", use: getUser)
        
        // MARK: - Middleware
        let tokenAuthMiddleware = Token.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthGroup = uses.grouped(tokenAuthMiddleware, guardAuthMiddleware)
        
        // MARK: - Protected routes
        // Usage:
        /// Route: {base-url}/api/v1/test/user/{user-id}
        /// AuthType -> Bearer Token -> Token: {token-value}
        // Response:
        /// { user }
        tokenAuthGroup.get("user", ":id", use: getUserProtected)
    }
    
    @Sendable
    func index(req: Request) async throws -> [User] {
        return try await User.query(on: req.db).all()
    }
    
    @Sendable
    func getUser(req: Request) async throws -> User {
        guard let user = try await User.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
                
        return user
    }
    
    @Sendable
    func getUserProtected(req: Request) async throws -> User {
        guard let user = try await User.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
                
        return user
    }
}
