import Foundation

extension Array where Element == LetterPlacement {

    func buildWord(with letters: [String], direction: Direction) -> String {
        return self
            .sorted { lhs, rhs in
                if direction == Direction.horizontal {
                    return lhs.position[1] < rhs.position[1] // Сортировка по столбцу
                } else if direction == Direction.vertical {
                    return lhs.position[0] < rhs.position[0] // Сортировка по строке
                } else {
                    return false // Если направление некорректно, не сортируем
                }
            }
            .map { letters[$0.tileIndex] } // Извлекаем буквы
            .joined()          // Объединяем в строку
    }

    func getIndexes() -> [Int] {
        return self.map { $0.tileIndex }
    }
}
