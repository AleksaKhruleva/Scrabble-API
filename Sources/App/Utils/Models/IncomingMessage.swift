import Foundation

struct IncomingMessage: Codable {
    let action: PlayerAction
    let roomID: UUID
    let kickPlayerID: UUID?
    let changingTiles: [Int]?
    let direction: Direction?
    let letters: [LetterPlacement]?
    let reaction: String?
}
