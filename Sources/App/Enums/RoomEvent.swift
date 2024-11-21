import Foundation

enum RoomEvent: String, Codable {
    case joinedRoom = "joined_room"
    case playerJoined = "player_joined"
    
    case roomChangedPrivacy = "room_changed_privacy"
    
    case kickedByAdmin = "kicked_by_admin"
    case playerKicked = "player_kicked"
    
    case leftRoom = "left_room"
    case playerLeft = "player_left"
    
    case skippedTurn = "skipped_turn"
    case playerSkippedTurn = "player_skipped_turn"
    
    case exhangedTiles = "exchanged_tiles"
    case playerExchangedTiles = "player_exchanged_tiles"
    
    case madeMove = "made_move"
    case playerMadeMove = "player_made_move"
    
    case placedWord = "placed_word"
    case playerPlacedWord = "player_placed_word"
    
    case roomClosed = "room_closed"
    
    case gameStarted = "game_started"
}
