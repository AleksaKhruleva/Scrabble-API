import Fluent
import Vapor

// tupoi xcode topchik👍🏿 👶🏻👼🏻

struct UserMigration: AsyncMigration {
    
    let schema = User.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
            .field("username", .string)
            .field("email", .string)
            .field("password", .string)
            .field("room_id", .uuid)
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
