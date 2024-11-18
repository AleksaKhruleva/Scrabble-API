import Vapor

struct CreateRoomDTO: Content {
    let isPrivate: Bool
    let timePerTurn: Int
    let maxPlayers: Int
}
