
import Foundation

private protocol Lock: Sendable {
    func lock()
    func unlock()
}

extension Lock {
    func around<T>(_ closure: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try closure()
    }

    func around(_ closure: () throws -> Void) rethrows {
        lock(); defer { unlock() }
        try closure()
    }
}

#if canImport(Darwin)
final class UnfairLock: Lock, @unchecked Sendable {
    private let unfairLock: os_unfair_lock_t

    init() {
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    fileprivate func lock() {
        os_unfair_lock_lock(unfairLock)
    }

    fileprivate func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }
}

#elseif canImport(Foundation)
extension NSLock: Lock {}
#else
#error("This platform needs a Lock-conforming type without Foundation.")
#endif

final class Protected<Value> {
    #if canImport(Darwin)
    private let lock = UnfairLock()
    #elseif canImport(Foundation)
    private let lock = NSLock()
    #else
    #error("This platform needs a Lock-conforming type without Foundation.")
    #endif

    private nonisolated(unsafe) var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read<U>(_ closure: (Value) throws -> U) rethrows -> U {
        try lock.around { try closure(self.value) }
    }

    @discardableResult
    func write<U>(_ closure: (inout Value) throws -> U) rethrows -> U {
        try lock.around { try closure(&self.value) }
    }

    func write(_ value: Value) {
        write { $0 = value }
    }
}

#if compiler(>=6)
extension Protected: Sendable {}
#endif

extension Protected where Value == Request.MutableState {
    func attemptToTransitionTo(_ state: Request.State) -> Bool {
        lock.around {
            guard value.state.canTransitionTo(state) else { return false }

            value.state = state

            return true
        }
    }

    func withState(perform: (Request.State) -> Void) {
        lock.around { perform(value.state) }
    }
}

extension Protected: Equatable where Value: Equatable {
    static func ==(lhs: Protected<Value>, rhs: Protected<Value>) -> Bool {
        lhs.read { left in rhs.read { right in left == right }}
    }
}

extension Protected: Hashable where Value: Hashable {
    func hash(into hasher: inout Hasher) {
        read { hasher.combine($0) }
    }
}
