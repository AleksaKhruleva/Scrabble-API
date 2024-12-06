import Vapor

struct APIKeyMiddleware: AsyncMiddleware {

    private let validAPIKey: String

    init(apiKey: String) {
        self.validAPIKey = apiKey
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let apiKey = request.headers["x-api-key"].first else {
            throw Abort(.unauthorized, reason: "Missing API key")
        }

        guard apiKey == validAPIKey else {
            throw Abort(.unauthorized, reason: "Invalid API key")
        }

        return try await next.respond(to: request)
    }
}
