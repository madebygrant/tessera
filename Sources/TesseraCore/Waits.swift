// Callers waiting for an app's window. A window event for the app re-checks
// at once; a 1s tick backs that up for apps that don't post AX notifications
// and handles timeouts.
@MainActor
final class Waits {
    private final class Wait {
        let app: String
        let deadline: Double
        let check: () -> Bool
        let onTimeout: (() -> Void)?
        var done = false
        init(app: String, deadline: Double, check: @escaping () -> Bool, onTimeout: (() -> Void)?) {
            self.app = app
            self.deadline = deadline
            self.check = check
            self.onTimeout = onTimeout
        }
    }

    static let fallback = 1.0
    private let scheduler: Scheduler
    private var waits: [Wait] = []
    private var tick: Cancellable?

    init(scheduler: Scheduler) { self.scheduler = scheduler }

    var isEmpty: Bool { waits.isEmpty }

    // `check` returns true once it has what it waited for.
    func start(app: String, timeout: Double, check: @escaping () -> Bool, onTimeout: (() -> Void)?) -> Cancellable {
        let wait = Wait(app: app, deadline: scheduler.now + timeout, check: check, onTimeout: onTimeout)
        waits.append(wait)
        scheduleTick()
        return Cancellable { [weak self, weak wait] in
            wait?.done = true
            self?.waits.removeAll { $0 === wait }
        }
    }

    // In start order, so an earlier entry for the same app claims the window first.
    func appChanged(_ process: AppProcess) {
        for wait in waits where !wait.done && process.matches(wait.app) {
            if wait.check() { wait.done = true }
        }
        waits.removeAll(where: \.done)
    }

    func cancelAll() {
        for wait in waits { wait.done = true }
        waits = []
        tick?.cancel()
        tick = nil
    }

    private func scheduleTick() {
        guard tick == nil, !waits.isEmpty else { return }
        tick = scheduler.after(Self.fallback) { [weak self] in
            guard let self else { return }
            self.tick = nil
            let now = self.scheduler.now
            for wait in self.waits where !wait.done {
                if wait.check() {
                    wait.done = true
                } else if now >= wait.deadline {
                    wait.done = true
                    wait.onTimeout?()
                }
            }
            self.waits.removeAll(where: \.done)
            self.scheduleTick()
        }
    }
}
