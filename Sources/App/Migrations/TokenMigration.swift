import Fluent
import Vapor

struct TokenMigration: AsyncMigration {
    
    let schema = Token.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
            .field("value", .string)
            .field("user_id", .string)
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
