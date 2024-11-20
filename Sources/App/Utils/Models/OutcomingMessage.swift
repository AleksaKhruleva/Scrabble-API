import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let newRoomPrivacy: Bool?
    let kickedPlayerID: UUID?
    let boardLayout: [[BonusType]]?
    let currentTurn: UUID?
    let leaderboard: [String: Int]?
    let playerTiles: [String]?
    
    init(
        event: RoomEvent,
        newPlayerInfo: PlayerInfo? = nil,
        newRoomPrivacy: Bool? = nil,
        kickedPlayerID: UUID? = nil,
        boardLayout: [[BonusType]]? = nil,
        currentTurn: UUID? = nil,
        leaderboard: [String: Int]? = nil,
        playerTiles: [String]? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
        self.boardLayout = boardLayout
        self.currentTurn = currentTurn
        self.leaderboard = leaderboard
        self.playerTiles = playerTiles
        self.newRoomPrivacy = newRoomPrivacy
    }
}
