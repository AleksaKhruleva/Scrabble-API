import Vapor

struct CreateRoomDTO: Content {
    let isPrivate: Bool
}
