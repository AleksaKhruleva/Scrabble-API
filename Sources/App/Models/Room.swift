import Fluent
import Vapor

final class Room: Model, @unchecked Sendable {
    static let schema = Schema.rooms.rawValue

    @ID(key: .id)
    var id: UUID?

    @OptionalField(key: "invite_code")
    var inviteCode: String?

    @Field(key: "is_private")
    var isPrivate: Bool

    @Parent(key: "admin_id")
    var admin: User

    @Children(for: \.$room)
    var players: [User]

    init() {}

    init(id: UUID? = nil, inviteCode: String?, isPrivate: Bool, adminID: UUID) {
        self.id = id
        self.inviteCode = inviteCode
        self.isPrivate = isPrivate
        self.$admin.id = adminID
    }
}
