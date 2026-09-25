
import Foundation

extension OperationQueue {
    convenience init(qualityOfService: QualityOfService = .default,
                     maxConcurrentOperationCount: Int = OperationQueue.defaultMaxConcurrentOperationCount,
                     underlyingQueue: DispatchQueue? = nil,
                     name: String? = nil,
                     startSuspended: Bool = false) {
        self.init()
        self.qualityOfService = qualityOfService
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.underlyingQueue = underlyingQueue
        self.name = name
        isSuspended = startSuspended
    }
}
