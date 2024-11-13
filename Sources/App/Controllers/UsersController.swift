import Vapor

struct UsersController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("api", "v1", "users")
        
        // MARK: - Non-protected routes
        users.get(use: index)
    }
    
    @Sendable
    func index(req: Request) async throws -> [User.Public] {
        let users = try await User.query(on: req.db).all()
        
        return users.map { $0.convertToPublic() }
    }
}
