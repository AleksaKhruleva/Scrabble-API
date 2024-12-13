import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: .prefer(try .init(configuration: .clientDefault)))
    ), as: .psql)

    // MARK: - Generating API-Key
    let apiKeyService = APIKeyService()
    let generatedApiKey = apiKeyService.generateAPIKey()
    apiKeyService.saveAPIKeyToEnvFile(app: app, apiKey: generatedApiKey)

    // MARK: - Setup API-Key
    // FIXME: - Develop new API-Key functionality
    // let apiKey = Environment.get("API_KEY") ?? generatedApiKey
    // app.logger.info("Loaded API_KEY: \(apiKey)")
    // app.middleware.use(APIKeyMiddleware(apiKey: apiKey))

    // MARK: - Setup Services
    let userService: UserServiceProtocol = UserService(db: app.db)
    app.register(userService)

    // MARK: - Setup Migrations
    app.migrations.add(CreateUserMigration())
    app.migrations.add(CreateRoomMigration())
    app.migrations.add(CreateRoomPlayerMigration())
    app.migrations.add(CreateTokenMigration())
    app.migrations.add(CreateWordMigration())
    try await app.autoMigrate().get()

    // MARK: - Register routes
    try routes(app)
}
