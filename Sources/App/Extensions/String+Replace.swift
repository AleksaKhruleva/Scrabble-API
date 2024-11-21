import Foundation

extension String {

    mutating func replaceCharacter(at index: Int, with newCharacter: Character) {
        let start = self.index(self.startIndex, offsetBy: index)
        self.replaceSubrange(start...start, with: String(newCharacter))
    }
}
