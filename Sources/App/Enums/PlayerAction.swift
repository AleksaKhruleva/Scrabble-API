import Foundation

enum PlayerAction: String, Codable {
    case joinRoom = "join_room"
    case startGame = "start_game"
    case pauseGame = "pause_game"
    case resumeGame = "resume_game"
    case leaveGame = "leave_game"
    case makeRoomPrivate = "make_room_private"
    case kickPlayer = "kick_player"
    case leaveRoom = "leave_room" // for everyone except admin
    case closeRoom = "close_room" // only for admin
    //    case makeMove = "make_move"
    //    case skipTurn = "skip_turn"
}
