import Vapor

struct JoinRoomDTO: Content {
    var inviteCode: String?
}
