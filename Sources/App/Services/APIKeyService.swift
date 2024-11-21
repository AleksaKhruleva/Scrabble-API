import Foundation
import Vapor

final class APIKeyService {

    let filePath = ".env"

    // Saving API-key to `.env` file
    func saveAPIKeyToEnvFile(app: Application, apiKey: String) {
        let newEntry = "API_KEY=\(apiKey)\n"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: filePath) {
            if let contents = try? String(contentsOfFile: filePath, encoding: .utf8) {
                if !contents.contains("API_KEY=") {
                    do {
                        let updatedContents = contents + newEntry
                        try updatedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
                        app.logger.info("API Key added to \(filePath).")
                    } catch {
                        app.logger.info("Failed to write to .env file: \(error)")
                    }
                }
            }
        } else {
            do {
                try newEntry.write(toFile: filePath, atomically: true, encoding: .utf8)
                app.logger.info("API Key saved to new file: \(filePath).")
            } catch {
                app.logger.info("Failed to create .env file: \(error)")
            }
        }
    }

    // Generating random API-key
    func generateAPIKey(length: Int = 32) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
