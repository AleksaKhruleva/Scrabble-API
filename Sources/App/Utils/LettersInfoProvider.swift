import Foundation

final class LettersInfoProvider: @unchecked Sendable {
    
    static let shared = LettersInfoProvider()
    private let lettersInfo: [Character: LetterInfo]
    
    private init() {
        lettersInfo = Self.loadLetterInfo()
    }
    
    private static func loadLetterInfo() -> [Character: LetterInfo] {
        guard let url = Bundle.module.url(forResource: "lettersInfo", withExtension: "json") else {
            print("Error: lettersInfo.json file not found")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let info = try JSONDecoder().decode([String: LetterInfo].self, from: data)
            return info.reduce(into: [:]) { result, entry in
                if let char = entry.key.first {
                    result[char] = entry.value
                }
            }
        } catch {
            print("Error loading lettersInfo.json: \(error)")
            return [:]
        }
    }
    
    func totalInitialQuantity() -> Int {
        lettersInfo.reduce(0) { result, entry in
            result + entry.value.initialQuantity
        }
    }
}
