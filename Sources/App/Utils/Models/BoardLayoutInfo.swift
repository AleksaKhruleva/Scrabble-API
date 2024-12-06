import Foundation

struct BoardLayoutInfo: Codable {
    let size: Int
    let tripleWord: [[Int]]
    let doubleWord: [[Int]]
    let tripleLetter: [[Int]]
    let doubleLetter: [[Int]]
}
