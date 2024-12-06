import Vapor

struct WordsController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("load-words") { req async throws -> String in
            let count = try await WordsProvider.shared.loadWords(on: req.db)
            return "\(count) words loaded successfully!"
        }
    }
}
