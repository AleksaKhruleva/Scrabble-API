import Fluent
import Vapor

struct CreateRoomPlayerMigration: AsyncMigration {

    let schema = RoomPlayer.schema

    func prepare(on database: FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()

            .field("room_id", .uuid, .required, .references("rooms", "id", onDelete: .cascade))
            .field("player_id", .uuid, .required, .references("users", "id", onDelete: .cascade))

            .unique(on: "room_id", "player_id")
            .unique(on: "player_id")
            .create()
    }

    func revert(on database: FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
