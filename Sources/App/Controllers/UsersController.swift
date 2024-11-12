import Vapor

struct UsersController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        
        users.get(use: index)
        users.post(use: create)
    }
    
    @Sendable
    func index(req: Request) async throws -> [User.Public] {
        let users = try await User.query(on: req.db).all()
        
        return users.map { $0.convertToPublic() }
    }
    
    @Sendable
    func create(_ req: Request) async throws -> User.Public {
        let user = try req.content.decode(User.self)
        
        try await user.save(on: req.db)
        return user.convertToPublic()
    }
}
