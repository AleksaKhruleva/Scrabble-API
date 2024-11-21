import Foundation

enum RoomEvent: String, Codable {
    case joinedRoom = "joined_room"
    case playerJoined = "player_joined"
    
    case roomChangedPrivacy = "room_changed_privacy"
    
    case kickedByAdmin = "kicked_by_admin"
    case playerKicked = "player_kicked"
    
    case leftRoom = "left_room"
    case playerLeft = "player_left"
    
    case exhangedTiles = "exchanged_tiles"
    case playerExchangedTiles = "player_exchanged_tiles"
    
    case endedTurn = "ended_turn"
    case playerEndedTurn = "player_ended_turn"
    
    case placedWord = "placed_word"
    case playerPlacedWord = "player_placed_word"
    
    case roomClosed = "room_closed"
    
    case gameEndedMuchEmptyTurns = "game_ended_much_empty_turns"
    
    case gameStarted = "game_started"
}
