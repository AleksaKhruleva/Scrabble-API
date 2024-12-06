import Vapor
import Fluent

final class WordsProvider: @unchecked Sendable {
    static let shared = WordsProvider()

    private init() {}

    func loadWords(on db: Database) async throws -> Int {
        guard let filePath = Bundle.module.path(forResource: "words", ofType: "txt") else {
            throw Abort(.internalServerError, reason: "File 'words.txt' not found")
        }

        do {
            let fileContents = try String(contentsOfFile: filePath)
            let words = fileContents.split(separator: "\n").map { String($0).uppercased() }
            let wordModels = words.map { Word(word: $0) }

            try await wordModels.create(on: db)
            return words.count
        } catch {
            throw Abort(.internalServerError, reason: "Failed to load words: \(error.localizedDescription)")
        }
    }
}
