import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let newRoomPrivacy: Bool?
    let kickedPlayerID: UUID?
    let leftPlayerID: UUID?
    let skippedPlayerID: UUID?
    let exchangedTilesPlayerID: UUID?
    let boardLayout: [[BonusType]]?
    let currentTurn: UUID?
    let leaderboard: [String: Int]?
    let playerTiles: [String]?
    
    init(
        event: RoomEvent,
        newPlayerInfo: PlayerInfo? = nil,
        newRoomPrivacy: Bool? = nil,
        kickedPlayerID: UUID? = nil,
        leftPlayerID: UUID? = nil,
        skippedPlayerID: UUID? = nil,
        exchangedTilesPlayerID: UUID? = nil,
        boardLayout: [[BonusType]]? = nil,
        currentTurn: UUID? = nil,
        leaderboard: [String: Int]? = nil,
        playerTiles: [String]? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
        self.leftPlayerID = leftPlayerID
        self.skippedPlayerID = skippedPlayerID
        self.exchangedTilesPlayerID = exchangedTilesPlayerID
        self.boardLayout = boardLayout
        self.currentTurn = currentTurn
        self.leaderboard = leaderboard
        self.playerTiles = playerTiles
        self.newRoomPrivacy = newRoomPrivacy
    }
}
