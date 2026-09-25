
import Dispatch
import Foundation

extension DispatchQueue {
    func after(_ delay: TimeInterval, execute closure: @escaping @Sendable () -> Void) {
        asyncAfter(deadline: .now() + delay, execute: closure)
    }
}
