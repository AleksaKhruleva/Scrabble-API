import Vapor

struct WebSocketController: RouteCollection {
    
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let sockets = routes.grouped("sockets")
        
        // MARK: - Middleware
        let tokenAuthMiddleware = Token.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthGroup = sockets.grouped(tokenAuthMiddleware, guardAuthMiddleware)
        
        tokenAuthGroup.webSocket("connect", onUpgrade: connect)
    }
    
    @Sendable
    func connect(req: Request, socket: WebSocket) {
        socket.onText {socket, message in
            Task {
                await handleMessage(socket: socket, message: message, req: req)
            }
        }
        
        socket.onClose.whenComplete { _ in
            Task {
                await handleConnectionClose(socket: socket, req: req)
            }
        }
    }
}

// MARK: - Private

extension WebSocketController {
    
    private func handleMessage(socket: WebSocket, message: String, req: Request) async {
        guard let incomingMessage = decodeIncomingMessage(from: message) else {
            // Send error: Unable to decode message
            return
        }
        await WebSocketManager.shared
            .receiveMessage(
                from: socket,
                incomingMessage: incomingMessage,
                req: req
            )
    }
    
    private func handleConnectionClose(socket: WebSocket, req: Request) async {
        await WebSocketManager.shared.handleUserClosedConnection(socket: socket, req: req)
    }
    
    private func decodeIncomingMessage(from message: String) -> IncomingMessage? {
        guard let messageData = message.data(using: .utf8) else {
            return nil
        }
        do {
            let incomingMessage = try JSONDecoder().decode(IncomingMessage.self, from: messageData)
            return incomingMessage
        } catch {
            return nil
        }
    }
}
