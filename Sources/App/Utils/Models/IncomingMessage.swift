import Foundation

struct IncomingMessage: Codable {
    let action: PlayerAction
    let roomID: UUID
    let kickPlayerID: UUID?
    let reaction: String?
}
