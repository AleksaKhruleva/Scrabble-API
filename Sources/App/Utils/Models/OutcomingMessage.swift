import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let kickedPlayerID: UUID?
    let leftPlayerID: UUID?
    let boardLayout: [[BonusType]]?
    let currentTurn: UUID?
    let leaderboard: [String: Int]?
    let playerTiles: [String]?
    
    init(
        event: RoomEvent,
        newPlayerInfo: PlayerInfo? = nil,
        kickedPlayerID: UUID? = nil,
        leftPlayerID: UUID? = nil,
        boardLayout: [[BonusType]]? = nil,
        currentTurn: UUID? = nil,
        leaderboard: [String: Int]? = nil,
        playerTiles: [String]? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
        self.leftPlayerID = leftPlayerID
        self.boardLayout = boardLayout
        self.currentTurn = currentTurn
        self.leaderboard = leaderboard
        self.playerTiles = playerTiles
    }
}
