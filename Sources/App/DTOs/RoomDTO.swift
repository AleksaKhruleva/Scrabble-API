import Vapor

struct RoomDTO: Content {
    var id: UUID?
    var inviteCode: String
    var isPrivate: Bool
    var adminID: UUID
    var players: [UUID]
}
