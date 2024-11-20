import Foundation

enum PlayerAction: String, Codable {
    case joinRoom = "join_room"
    case startGame = "start_game"
    //    case pauseGame = "pause_game"
    //    case endGame = "end_game"
    case changeRoomPrivacy = "change_room_privacy"
    case kickPlayer = "kick_player"
    //    case makeMove = "make_move"
    //    case skipTurn = "skip_turn"
}
