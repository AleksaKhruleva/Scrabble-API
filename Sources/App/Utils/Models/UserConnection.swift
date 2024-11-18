import Foundation
import Vapor

struct UserConnection {
    let userID: UUID
    let socket: WebSocket
}
