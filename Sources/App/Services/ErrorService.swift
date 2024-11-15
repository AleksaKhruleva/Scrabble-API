import Vapor
import Fluent

final class ErrorService: @unchecked Sendable {
    
    static let shared = ErrorService()
    
    private init() {}
    
    func handleError(_ error: Error) throws {
        if let abortError = error as? Abort {
            throw Abort(abortError.status, reason: abortError.reason)
        }
        if let _ = error as? DatabaseError {
            throw Abort(.internalServerError, reason: "Database operation failed")
        }
        throw Abort(.internalServerError, reason: error.localizedDescription)
    }
}
