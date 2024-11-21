import Fluent
import Vapor

final class Room: Model, @unchecked Sendable {

    static let schema = Schema.rooms.rawValue

    // MARK: - Basic room info
    @ID(key: .id)
    var id: UUID?

    @Field(key: "invite_code")
    var inviteCode: String

    @Field(key: "is_private")
    var isPrivate: Bool

    @Parent(key: "admin_id")
    var admin: User

    @Field(key: "game_status")
    var gameStatus: String

    // MARK: - Game data
    @Field(key: "leaderboard")
    var leaderboard: [String: Int]

    @Field(key: "tiles_left")
    var tilesLeft: [String: Int]

    @Field(key: "board")
    var board: String

    @Field(key: "turn_order")
    var turnOrder: [UUID]

    @Field(key: "current_turn_index")
    var currentTurnIndex: Int

    @Field(key: "time_per_turn")
    var timePerTurn: Int

    @Field(key: "max_players")
    var maxPlayers: Int

    // MARK: - Player data and related resources
    @Children(for: \.$room)
    var players: [RoomPlayer]

    @Field(key: "players_tiles")
    var playersTiles: [String: [String]]

    @Field(key: "current_skipped_turns")
    var currentSkippedTurns: Int

    @Field(key: "placed_words")
    var placedWords: [String]

    init() {}

    init(
        id: UUID? = nil,
        inviteCode: String,
        isPrivate: Bool,
        adminID: UUID,
        timePerTurn: Int,
        maxPlayers: Int
    ) {
        self.id = id
        self.inviteCode = inviteCode
        self.isPrivate = isPrivate
        self.$admin.id = adminID
        self.gameStatus = GameStatus.waiting.rawValue
        self.timePerTurn = timePerTurn
        self.maxPlayers = maxPlayers
        reset()
    }
}

extension Room {

    func reset() {
        self.leaderboard = [:]
        self.tilesLeft = [:]
        self.board = ""
        self.turnOrder = []
        self.currentTurnIndex = 0
        self.playersTiles = [:]
        self.placedWords = []
        self.currentSkippedTurns = 0
    }

    func toDTO(for userID: UUID) -> RoomDTO {
        let playersInfo: [String: String] = players.reduce(into: [:]) { result, roomPlayer in
            let playerID = roomPlayer.$player.id.uuidString
            let username = roomPlayer.player.username
            result[playerID] = username
        }

        return RoomDTO(
            id: id,
            currentUserID: userID,
            inviteCode: inviteCode,
            isPrivate: isPrivate,
            adminID: $admin.id,
            players: playersInfo,
            timePerTurn: timePerTurn,
            maxPlayers: maxPlayers
        )
    }
}
