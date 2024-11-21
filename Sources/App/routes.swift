import Fluent
import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AuthController())
    try app.register(collection: UsersController())
    try app.register(collection: RoomController())
    try app.register(collection: WebSocketController())
    try app.register(collection: WordsController())
}
