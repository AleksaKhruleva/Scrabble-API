import Vapor

struct RoomDTO: Content {
    let id: UUID?
    let inviteCode: String
    let isPrivate: Bool
    let adminID: UUID
    let players: [UUID]
}
