import Fluent
import Vapor

struct CreateRoomMigration: AsyncMigration {
    
    let schema = Room.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
            .field("invite_code", .string)
            .field("is_private", .bool, .required)
            .field("admin_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .unique(on: "invite_code")
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
