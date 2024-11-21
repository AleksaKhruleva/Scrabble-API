import Foundation

struct OutcomingMessage: Codable {
    let event: RoomEvent
    let newPlayerInfo: PlayerInfo?
    let newRoomPrivacy: Bool?
    let kickedPlayerID: UUID?
    let leftPlayerID: UUID?
    let exchangedTilesPlayerID: UUID?
    let endedTurnPlayerID: UUID?
    let placedWordPlayerID: UUID?
    let newWord: String?
    let scoredPoints: Int?
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
        exchangedTilesPlayerID: UUID? = nil,
        endedTurnPlayerID: UUID? = nil,
        placedWordPlayerID: UUID? = nil,
        newWord: String? = nil,
        scoredPoints: Int? = nil,
        boardLayout: [[BonusType]]? = nil,
        currentTurn: UUID? = nil,
        leaderboard: [String: Int]? = nil,
        playerTiles: [String]? = nil
    ) {
        self.event = event
        self.newPlayerInfo = newPlayerInfo
        self.kickedPlayerID = kickedPlayerID
        self.leftPlayerID = leftPlayerID
        self.exchangedTilesPlayerID = exchangedTilesPlayerID
        self.endedTurnPlayerID = endedTurnPlayerID
        self.placedWordPlayerID = placedWordPlayerID
        self.newWord = newWord
        self.scoredPoints = scoredPoints
        self.boardLayout = boardLayout
        self.currentTurn = currentTurn
        self.leaderboard = leaderboard
        self.playerTiles = playerTiles
        self.newRoomPrivacy = newRoomPrivacy
    }
}
