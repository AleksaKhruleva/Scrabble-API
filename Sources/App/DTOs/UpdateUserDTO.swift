import Vapor

struct UpdateUserDTO: Content {
    let username: String?
    let email: String?
    let password: String?
}
