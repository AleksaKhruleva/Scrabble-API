import Fluent
import Vapor

struct RoomMigration: AsyncMigration {
    
    let schema = Token.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
            .unique(on: "invite_code") //("invite_code", .string)
            .field("is_private", .string)
            .field("admin_id", .uuid)
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
