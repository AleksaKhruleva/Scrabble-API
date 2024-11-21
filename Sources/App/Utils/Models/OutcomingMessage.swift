import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let kickedPlayerID: UUID?
    let leftPlayerID: UUID?
    let boardLayout: [[BonusType]]?
    let currentTurn: UUID?
    let playerTiles: [String]?
    let newAdminID: UUID?
    let winnerID: UUID?
    
    init(
        event: RoomEvent,
        newPlayerInfo: PlayerInfo? = nil,
        kickedPlayerID: UUID? = nil,
        leftPlayerID: UUID? = nil,
        boardLayout: [[BonusType]]? = nil,
        currentTurn: UUID? = nil,
        playerTiles: [String]? = nil,
        newAdminID: UUID? = nil,
        winnerID: UUID? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
        self.leftPlayerID = leftPlayerID
        self.boardLayout = boardLayout
        self.currentTurn = currentTurn
        self.playerTiles = playerTiles
        self.newAdminID = newAdminID
        self.winnerID = winnerID
    }
}
