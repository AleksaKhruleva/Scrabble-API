import Vapor

struct RoomDTO: Content {
    let id: UUID?
    let currentUserID: UUID
    let inviteCode: String
    let isPrivate: Bool
    let adminID: UUID
    let players: [String: String]
    let timePerTurn: Int
    let maxPlayers: Int
}
