@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("App Tests with PostgreSQL", .serialized)
struct AuthControllerTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            app.logger.logLevel = .error
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    @Test("User Registration")
    func test_register_withValidData_shouldReturnToken() async throws {
        let user = RegisterUserDTO(username: "testuser", email: "test@example.com", password: "password123")
        
        try await withApp { app in
            try await app.test(.POST, "api/v1/auth/register", beforeRequest: { req in
                try req.content.encode(user)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let token = try res.content.decode(Token.self)
                #expect(token.value != "")
            })
        }
    }
    
    @Test("User Registration with duplicate email")
    func test_register_withDuplicateEmail_shouldReturnServerError() async throws {
        let registerUser = RegisterUserDTO(username: "testuser", email: "test@example.com", password: "password123")
        let user = User(
            username: registerUser.username,
            email: registerUser.email,
            password: try Bcrypt.hash(registerUser.password)
        )
        
        try await withApp { app in
            try await user.save(on: app.db)
            
            try await app.test(.POST, "api/v1/auth/register", beforeRequest: { req in
                try req.content.encode(registerUser)
            }, afterResponse: { res async throws in
                #expect(res.status == .internalServerError)
            })
        }
    }
    
    @Test("User Login")
    func test_login_withValidCredentials_shouldReturnToken() async throws {
        let user = User(username: "testuser", email: "test@example.com", password: try Bcrypt.hash("password123"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            
            try await app.test(.POST, "api/v1/auth/login", beforeRequest: { req in
                let basicAuth = BasicAuthorization(username: "test@example.com", password: "password123")
                req.headers.basicAuthorization = basicAuth
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let token = try res.content.decode(Token.self)
                #expect(token.value != "")
            })
        }
    }
    
    @Test("User Login with invalid password")
    func test_login_withInvalidPassword_shouldReturnError() async throws {
        let user = User(username: "testuser", email: "test@example.com", password: try Bcrypt.hash("password123"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            
            try await app.test(.POST, "api/v1/auth/login", beforeRequest: { req in
                let basicAuth = BasicAuthorization(username: "test@example.com", password: "InvalidPassword")
                req.headers.basicAuthorization = basicAuth
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }
    
    @Test("User Login with invalid email")
    func test_login_withInvalidEmail_shouldReturnError() async throws {
        let user = User(username: "testuser", email: "test@example.com", password: try Bcrypt.hash("password123"))
        
        try await withApp { app in
            try await user.save(on: app.db)
            
            try await app.test(.POST, "api/v1/auth/login", beforeRequest: { req in
                let basicAuth = BasicAuthorization(username: "invalid@example.com", password: "password123")
                req.headers.basicAuthorization = basicAuth
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }
}
