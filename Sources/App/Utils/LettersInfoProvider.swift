import Foundation

final class LettersInfoProvider: @unchecked Sendable {

    static let shared = LettersInfoProvider()
    private let lettersInfo: [String: LetterInfo]

    private init() {
        lettersInfo = Self.loadLetterInfo()
    }

    private static func loadLetterInfo() -> [String: LetterInfo] {
        guard let url = Bundle.module.url(forResource: "lettersInfo", withExtension: "json") else {
            print("Error: lettersInfo.json file not found")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: LetterInfo].self, from: data)
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

    func initialQuantities() -> [String: Int] {
        lettersInfo.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.initialQuantity
        }
    }

    func initialWeights() -> [String: Int] {
        lettersInfo.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.weight
        }
    }
}
