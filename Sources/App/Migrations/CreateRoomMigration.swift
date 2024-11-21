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
            .field("tiles_left", .json, .required)
            .field("board", .string, .required)
            .field("turn_order", .array(of: .uuid), .required)
            .field("current_turn_index", .int, .required)
            .field("time_per_turn", .int, .required)
            .field("max_players", .int, .required)

            .field("players_tiles", .json, .required)
            .field("placed_words", .array(of: .string), .required)
            .field("current_skipped_turns", .int, .required)

            .unique(on: "invite_code")
            .create()
    }

    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
