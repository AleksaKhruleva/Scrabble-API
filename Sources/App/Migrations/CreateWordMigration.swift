import Fluent
import Vapor

struct CreateWordMigration: AsyncMigration {

    let schema = Word.schema

    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()

            .field("word", .string, .required)

            .unique(on: "word")
            .create()
    }

    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
