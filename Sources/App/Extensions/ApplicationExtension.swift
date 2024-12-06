import Vapor

extension Application {
    func service<T: Sendable>(_ type: T.Type) -> T {
        guard let service = self.storage[GenericStorageKey<T>.self] else {
            fatalError("\(T.self) not configured. Register it in configure.swift")
        }
        return service
    }

    func register<T: Sendable>(_ service: T) {
        self.storage[GenericStorageKey<T>.self] = service
    }
}

private struct GenericStorageKey<T: Sendable>: StorageKey {
    typealias Value = T
}
