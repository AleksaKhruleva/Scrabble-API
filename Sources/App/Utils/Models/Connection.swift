import Foundation
import Vapor

struct Connection {
    let userID: UUID
    let socket: WebSocket
}
