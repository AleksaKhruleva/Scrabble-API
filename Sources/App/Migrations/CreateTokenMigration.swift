import Fluent
import Vapor

struct CreateTokenMigration: AsyncMigration {

    let schema = Token.schema

    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()

            .field("value", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))

            .unique(on: "user_id")
            .create()
    }

    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
