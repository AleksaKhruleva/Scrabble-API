import Fluent
import Vapor

// tupoi xcode topchik👍🏿 👶🏻👼🏻

struct CreateUserMigration: AsyncMigration {

    let schema = User.schema

    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()

            .field("username", .string, .required)
            .field("email", .string, .required)
            .field("password", .string, .required)

            .unique(on: "email")
            .create()
    }

    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
