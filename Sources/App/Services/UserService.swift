import Vapor
import Fluent

protocol UserServiceProtocol: Sendable {
    func fetchUserID(req: Request) async throws -> UUID
}

final class UserService: UserServiceProtocol, @unchecked Sendable {

    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func fetchUserID(req: Request) async throws -> UUID {
        guard let tokenValue = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing or invalid token")
        }

        guard let token = try await Token.query(on: db)
            .filter("value", .equal, tokenValue)
            .first()
        else {
            throw Abort(.unauthorized, reason: "Invalid or expired token")
        }

        return token.$user.id
    }
}
