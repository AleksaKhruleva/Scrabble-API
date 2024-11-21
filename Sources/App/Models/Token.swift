import Fluent
import Vapor

final class Token: Model, Content, @unchecked Sendable {

    static let schema = Schema.tokens.rawValue

    @ID(key: .id)
    var id: UUID?

    @Field(key: "value")
    var value: String

    @Parent(key: "user_id")
    var user: User

    init() { }

    init(id: UUID? = nil, value: String, userID: User.IDValue) {
        self.id = id
        self.value = value
        self.$user.id = userID
    }
}

extension Token {
    static func generate(for user: User) throws -> Token {
        let random = [UInt8].random(count: 32).base64
        return try Token(value: random, userID: user.requireID())
    }
}

extension Token: ModelTokenAuthenticatable {
    typealias User = App.User

    static let valueKey = \Token.$value
    static let userKey = \Token.$user

    var isValid: Bool {
        true
    }
}
