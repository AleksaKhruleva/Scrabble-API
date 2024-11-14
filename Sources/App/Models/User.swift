import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = Schema.users.rawValue
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "username")
    var username: String
    
    @Field(key: "email")
    var email: String
    
    @Field(key: "password")
    var password: String
    
    @OptionalParent(key: "room_id")
    var room: Room?
    
    init() { }
    
    init(id: UUID? = nil, username: String, email: String, password: String, roomID: UUID? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.password = password
        self.$room.id = roomID
    }
    
    final class Public: Content {
        var id: UUID?
        var username: String
        var email: String
        
        init(id: UUID?, username: String, email: String) {
            self.id = id
            self.username = username
            self.email = email
        }
    }
}

extension User {
    func convertToPublic() -> User.Public {
        return User.Public(id: id, username: username, email: email)
    }
}

extension User: ModelAuthenticatable {
    static let usernameKey = \User.$email
    static let passwordHashKey = \User.$password
    
    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.password)
    }
}
