import Fluent
import Vapor

final class RoomPlayer: Model, @unchecked Sendable {

    static let schema = Schema.roomPlayers.rawValue

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "room_id")
    var room: Room

    @Parent(key: "player_id")
    var player: User

    init() {}

    init(id: UUID? = nil, roomID: UUID, playerID: UUID) {
        self.id = id
        self.$room.id = roomID
        self.$player.id = playerID
    }
}
