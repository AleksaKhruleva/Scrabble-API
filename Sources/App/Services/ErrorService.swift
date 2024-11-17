import Vapor
import Fluent

final class ErrorService: @unchecked Sendable {
    
    static let shared = ErrorService()
    
    private init() {}
    
    func handleError(_ error: Error) -> Error {
        if let abortError = error as? Abort {
            return Abort(abortError.status, reason: abortError.reason)
        }
        if let _ = error as? DatabaseError {
            return Abort(.internalServerError, reason: "Database operation failed")
        }
        return Abort(.internalServerError, reason: error.localizedDescription)
    }
}
