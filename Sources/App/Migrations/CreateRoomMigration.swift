import Fluent
import Vapor

struct CreateRoomMigration: AsyncMigration {
    
    let schema = Room.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
        
            .field("invite_code", .string, .required)
            .field("is_private", .bool, .required)
            .field("admin_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("game_status", .string, .required)
        
            .field("leaderboard", .json, .required)
            .field("tiles_left", .int, .required)
            .field("board", .string, .required)
        
            .field("player_tiles", .json, .required)
            .field("placed_words", .array(of: .string), .required)
        
            .unique(on: "invite_code")
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
