import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let kickedPlayerID: UUID?
    
    init(
        event: RoomEvent,
        newPlayerInfo: PlayerInfo? = nil,
        kickedPlayerID: UUID? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
    }
}
