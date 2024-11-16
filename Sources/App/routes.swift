import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    app.get("hello") { req async -> String in
        "Hello, world!"
    }
    
    try app.register(collection: AuthController())
    try app.register(collection: UsersController())
    try app.register(collection: RoomController())
    try app.register(collection: WebSocketController())
}
