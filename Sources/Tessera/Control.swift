import Foundation

// The CLI and the running app talk over a Mach message port: no socket file
// to clean up, and a reply comes back synchronously.
enum Control {
    static var portName: CFString { "local.tessera.control" as CFString }

    enum Command: Int32 {
        case status = 1, cycle, push
    }

    enum Outcome {
        case reply(String)
        case notRunning
        // The app took the request but didn't answer in time; it still runs it.
        case busy
    }

    // Only status waits for an answer; cycle and push just need delivering.
    static func send(_ command: Command, _ payload: String = "") -> Outcome {
        guard let remote = CFMessagePortCreateRemote(nil, portName) else { return .notRunning }
        let wantsReply = command == .status
        var reply: Unmanaged<CFData>?
        let data = Data(payload.utf8) as CFData
        let status = wantsReply
            ? CFMessagePortSendRequest(remote, command.rawValue, data, 2, 5, CFRunLoopMode.defaultMode.rawValue, &reply)
            : CFMessagePortSendRequest(remote, command.rawValue, data, 2, 0, nil, nil)
        switch status {
        case kCFMessagePortSuccess:
            return .reply(reply.map { String(decoding: $0.takeRetainedValue() as Data, as: UTF8.self) } ?? "")
        case kCFMessagePortSendTimeout, kCFMessagePortReceiveTimeout:
            return .busy
        default:
            return .notRunning
        }
    }

    @MainActor
    final class Server {
        var handler: ((Command, String) -> String)?
        private var port: CFMessagePort?

        func start() {
            var context = CFMessagePortContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil
            )
            port = CFMessagePortCreateLocal(nil, portName, { _, id, data, info in
                guard let info, let command = Command(rawValue: id) else { return nil }
                let server = Unmanaged<Server>.fromOpaque(info).takeUnretainedValue()
                let payload = data.map { String(decoding: $0 as Data, as: UTF8.self) } ?? ""
                let reply = MainActor.assumeIsolated { server.handler?(command, payload) ?? "" }
                return Unmanaged.passRetained(Data(reply.utf8) as CFData)
            }, &context, nil)
            guard let port else {
                return log.error("control port taken; is another Tessera running?")
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, port, 0), .commonModes)
        }
    }
}

// `tessera status | cycle [step] | push`, for the bar and for debugging.
enum CLI {
    static let commands: Set<String> = ["status", "cycle", "push"]

    static func run(_ args: [String]) -> Int32 {
        let outcome: Control.Outcome
        switch args.first {
        case "status":
            outcome = Control.send(.status)
        case "cycle":
            let step = args.count > 1 ? Int(args[1]) : 1
            guard let step else { return fail("cycle takes a whole number, e.g. `tessera cycle -1`") }
            outcome = Control.send(.cycle, "\(step)")
        case "push":
            outcome = Control.send(.push)
        default:
            return fail("usage: tessera status | cycle [step] | push")
        }
        switch outcome {
        case let .reply(text):
            if !text.isEmpty { print(text) }
            return 0
        case .notRunning:
            return fail("Tessera isn't running")
        case .busy:
            return fail("Tessera is running but didn't answer in 5s; an app it's talking to may be hung")
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("tessera: \(message)\n".utf8))
        return 1
    }
}
