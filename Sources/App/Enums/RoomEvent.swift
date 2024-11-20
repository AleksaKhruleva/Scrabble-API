import Foundation

enum RoomEvent: String, Codable {
    case joinedRoom = "joined_room"
    case newPlayerJoined = "new_player_joined"
    
    case roomChangedPrivacy = "room_changed_privacy"
    
    case kickedByAdmin = "kicked_by_admin"
    case playerWasKicked = "player_was_kicked"
    
    case gameStarted = "game_started"
}
