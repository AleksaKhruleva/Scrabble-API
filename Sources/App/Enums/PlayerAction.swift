import Foundation

enum PlayerAction: String, Codable {
    case joinRoom = "join_room"
    case startGame = "start_game"
    //    case pauseGame = "pause_game"
    //    case endGame = "end_game"
    case changeRoomPrivacy = "change_room_privacy"
    case kickPlayer = "kick_player"
    case leaveRoom = "leave_room" // for everyone except admin
    case closeRoom = "close_room" // only for admin
    case endTurn = "end_turn"
    case placeWord = "place_word"
    case exchangeTiles = "exchange_tiles"
}
