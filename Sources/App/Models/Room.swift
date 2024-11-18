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
        self.leaderboard = [:]
        self.tilesLeft = [:]
        self.board = ""
        self.turnOrder = []
        self.currentTurnIndex = 0
        self.timePerTurn = timePerTurn
        self.maxPlayers = maxPlayers
        self.playersTiles = [:]
        self.placedWords = []
    }
}

extension Room {
    func toDTO() -> RoomDTO {
        RoomDTO(
            id: id,
            inviteCode: inviteCode,
            isPrivate: isPrivate,
            adminID: $admin.id,
            players: players.map { $0.$player.id },
            timePerTurn: timePerTurn,
            maxPlayers: maxPlayers
        )
    }
}
