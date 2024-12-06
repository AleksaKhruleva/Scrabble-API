import Vapor

struct RegisterUserDTO: Content {
    let username: String
    let email: String
    let password: String
}
