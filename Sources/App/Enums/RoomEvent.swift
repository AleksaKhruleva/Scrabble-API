import Foundation

enum RoomEvent: String, Codable {
    case joinedRoom = "joined_room"
    case playerJoined = "player_joined"
    
    case roomReady = "room_ready"
    case roomWaiting = "room_waiting"
    case roomWasMadePrivate = "room_was_made_private"
    case roomClosed = "room_closed"
    
    case kickedByAdmin = "kicked_by_admin"
    case playerKicked = "player_kicked"
    
    case leftRoom = "left_room"
    case playerLeft = "player_left"
    
    case gameStarted = "game_started"
    case gamePaused = "game_paused"
    case gameResumed = "game_resumed"
}
