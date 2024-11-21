import Foundation

enum PlayerAction: String, Codable {
    case joinRoom = "join_room"
    case startGame = "start_game"
    case changeRoomPrivacy = "change_room_privacy"
    case endTurn = "end_turn"
    case skipTurn = "skip_turn"
    case suggestToEndGame = "suggest_end_game"
    case placeWord = "place_word"
    case exchangeTiles = "exchange_tiles"
    case pauseGame = "pause_game"
    case resumeGame = "resume_game"
    case leaveGame = "leave_game"
    case kickPlayer = "kick_player"
    case leaveRoom = "leave_room"
    case sendReaction = "send_reaction"
}
