import Vapor

struct JoinRoomDTO: Content {
    let inviteCode: String?
}
