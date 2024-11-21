import Fluent
import Vapor

final class Word: Model, @unchecked Sendable {

    static let schema = Schema.words.rawValue

    @ID(key: .id)
    var id: UUID?

    @Field(key: "word")
    var word: String

    init() { }

    init(id: UUID? = nil, word: String) {
        self.id = id
        self.word = word
    }
}
