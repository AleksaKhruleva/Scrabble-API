import Vapor
import Fluent

final class WordGameService {

    private let boardSize = BoardLayoutProvider.shared.size

    func calculateScore(
        letters: [LetterPlacement],
        board: String,
        boardLayout: [[BonusType]],
        tileWeights: [String: Int]
    ) -> Int {
        var totalScore = 0
        var wordMultiplier = 1

        for letterPlacement in letters {
            let row = letterPlacement.position[0]
            let col = letterPlacement.position[1]
            let index = row * boardSize + col

            let letter = board[board.index(board.startIndex, offsetBy: index)]

            guard let letterWeight = tileWeights[String(letter)] else {
                continue
            }

            let bonus = boardLayout[row][col]

            switch bonus {
            case .doubleLetter:
                totalScore += letterWeight * 2
            case .tripleLetter:
                totalScore += letterWeight * 3
            case .doubleWord:
                totalScore += letterWeight
                wordMultiplier *= 2
            case .tripleWord:
                totalScore += letterWeight
                wordMultiplier *= 3
            case .none:
                totalScore += letterWeight
            }
        }

        return totalScore * wordMultiplier
    }

    func findAllWords(
        from letters: [LetterPlacement],
        forWord mainWord: String,
        direction: Direction,
        board: String
    ) -> [String] {
        var words = [String]()

        for letter in letters {
            let row = letter.position[0]
            let col = letter.position[1]
            if direction == .horizontal {
                let verticalWord = findWord(row: row, col: col, direction: .vertical, board: board)
                if verticalWord.count > 1 {
                    words.append(verticalWord)
                }
            } else {
                let horizontalWord = findWord(row: row, col: col, direction: .horizontal, board: board)
                if horizontalWord.count > 1 {
                    words.append(horizontalWord)
                }
            }
        }

        return words
    }

    func validateWords(_ words: [String], on db: Database) async throws {
        for word in words {
            guard try await isValidWord(word, on: db) else {
                throw Abort(.badRequest, reason: "Invalid word: \(word)")
            }
        }
    }

    func isValidWord(_ word: String, on db: Database) async throws -> Bool {
        let count = try await Word.query(on: db)
            .filter(\.$word == word.uppercased())
            .count()

        return count > 0
    }

    func placeLetters(
        from letters: [LetterPlacement],
        withTiles tiles: [String],
        board: inout String
    ) throws -> Int {
        var sameLetterCount = 0
        let boardSize = 15

        for letter in letters {
            let row = letter.position[0]
            let col = letter.position[1]
            let index = row * boardSize + col

            let charAtIndex = board[board.index(board.startIndex, offsetBy: index)]

            guard charAtIndex == "." || charAtIndex == Character(tiles[letter.tileIndex]) else {
                throw Abort(.badRequest, reason: "The tile [\(row);\(col)] is used by another letter")
            }

            if charAtIndex == Character(tiles[letter.tileIndex]) {
                sameLetterCount += 1
            }

            board.replaceCharacter(at: index, with: Character(tiles[letter.tileIndex]))
        }

        return sameLetterCount
    }

}

extension WordGameService {

    private func findWord(row: Int, col: Int, direction: Direction, board: String) -> String {
        var word = ""
        var rowPtr = row
        var columnPtr = col

        func charAt(index: Int) -> Character {
            return board[board.index(board.startIndex, offsetBy: index)]
        }

        func index(row: Int, col: Int) -> Int {
            return row * boardSize + col
        }

        while rowPtr >= 0, columnPtr >= 0,
              charAt(index: index(row: rowPtr, col: columnPtr)) != ".",
              charAt(index: index(row: rowPtr, col: columnPtr)) != " " {
            if direction == .horizontal {
                columnPtr -= 1
            } else {
                rowPtr -= 1
            }
        }

        if direction == .horizontal {
            columnPtr += 1
        } else {
            rowPtr += 1
        }

        while rowPtr < boardSize, columnPtr < boardSize,
                charAt(index: index(row: rowPtr, col: columnPtr)) != ".",
                charAt(index: index(row: rowPtr, col: columnPtr)) != " " {
            word.append(charAt(index: index(row: rowPtr, col: columnPtr)))
            if direction == .horizontal {
                columnPtr += 1
            } else {
                rowPtr += 1
            }
        }

        return word
    }
}
