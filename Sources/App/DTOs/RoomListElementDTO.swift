import Vapor

struct RoomListElementDTO: Content {
    let id: UUID?
    let inviteCode: String
    let adminID: UUID
    let gameStatus: String
    let timePerTurn: Int
    let maxPlayers: Int
}
