import Foundation

final class BoardLayoutProvider: @unchecked Sendable {

    static let shared = BoardLayoutProvider()
    let size: Int
    let layout: [[BonusType]]

    private init() {
        if let boardData = Self.loadBoardLayout() {
            self.size = boardData.size
            self.layout = Self.createBoardLayout(from: boardData)
        } else {
            print("Error loading boardLayout.json. Using default 15x15 board size without bonuses.")
            self.size = 15
            self.layout = Array(repeating: Array(repeating: .none, count: 15), count: 15)
        }
    }

    private static func loadBoardLayout() -> BoardLayoutInfo? {
        guard let url = Bundle.module.url(forResource: "boardLayout", withExtension: "json") else {
            print("Error: boardLayout.json file not found")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BoardLayoutInfo.self, from: data)
        } catch {
            print("Error loading boardLayout.json: \(error)")
            return nil
        }
    }

    private static func createBoardLayout(from data: BoardLayoutInfo) -> [[BonusType]] {
        let emptyRow: [BonusType] = Array(repeating: .none, count: data.size)
        var board: [[BonusType]] = Array(repeating: emptyRow, count: data.size)

        for position in data.doubleLetter {
            board[position[0]][position[1]] = .doubleLetter
        }
        for position in data.tripleLetter {
            board[position[0]][position[1]] = .tripleLetter
        }
        for position in data.doubleWord {
            board[position[0]][position[1]] = .doubleWord
        }
        for position in data.tripleWord {
            board[position[0]][position[1]] = .tripleWord
        }

        return board
    }
}
