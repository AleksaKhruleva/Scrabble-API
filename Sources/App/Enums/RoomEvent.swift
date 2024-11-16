import Foundation

enum RoomEvent: String, Codable {
    case joinedRoom = "joined_room"
    case newPlayerJoined = "new_player_joined"
    
    case roomWasMadePrivate = "room_was_made_private"
    
    case kickedByAdmin = "kicked_by_admin"
    case playerWasKicked = "player_was_kicked"
}
