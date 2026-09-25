
#if canImport(SystemConfiguration)

import Foundation
import SystemConfiguration

@available(macOS, deprecated: 14.4, message: "Use NWPathMonitor instead.")
@available(iOS, deprecated: 17.4, message: "Use NWPathMonitor instead.")
@available(watchOS, deprecated: 9.4, message: "Use NWPathMonitor instead.")
@available(tvOS, deprecated: 17.4, message: "Use NWPathMonitor instead.")
@available(visionOS, deprecated: 1.4, message: "Use NWPathMonitor instead.")
open class NetworkReachabilityManager: @unchecked Sendable {
    public enum NetworkReachabilityStatus: Equatable, Sendable {
        case unknown
        case notReachable
        case reachable(ConnectionType)

        init(_ flags: SCNetworkReachabilityFlags) {
            guard flags.isActuallyReachable else { self = .notReachable; return }

            var networkStatus: NetworkReachabilityStatus = .reachable(.ethernetOrWiFi)

            if flags.isCellular { networkStatus = .reachable(.cellular) }

            self = networkStatus
        }

        public enum ConnectionType: Sendable {
            case ethernetOrWiFi
            case cellular
        }
    }

    public typealias Listener = @Sendable (NetworkReachabilityStatus) -> Void

    public static let `default` = NetworkReachabilityManager()

    open var isReachable: Bool { isReachableOnCellular || isReachableOnEthernetOrWiFi }

    open var isReachableOnCellular: Bool { status == .reachable(.cellular) }

    open var isReachableOnEthernetOrWiFi: Bool { status == .reachable(.ethernetOrWiFi) }

    public let reachabilityQueue = DispatchQueue(label: "org.alamofire.reachabilityQueue")

    open var flags: SCNetworkReachabilityFlags? {
        var flags = SCNetworkReachabilityFlags()

        return SCNetworkReachabilityGetFlags(reachability, &flags) ? flags : nil
    }

    open var status: NetworkReachabilityStatus {
        flags.map(NetworkReachabilityStatus.init) ?? .unknown
    }

    struct MutableState {
        var listener: Listener?
        var listenerQueue: DispatchQueue?
        var previousStatus: NetworkReachabilityStatus?
    }

    private let reachability: SCNetworkReachability

    private let mutableState = Protected(MutableState())

    public convenience init?(host: String) {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else { return nil }

        self.init(reachability: reachability)
    }

    public convenience init?() {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)

        guard let reachability = SCNetworkReachabilityCreateWithAddress(nil, &zero) else { return nil }

        self.init(reachability: reachability)
    }

    private init(reachability: SCNetworkReachability) {
        self.reachability = reachability
    }

    deinit {
        stopListening()
    }

    @preconcurrency
    @discardableResult
    open func startListening(onQueue queue: DispatchQueue = .main,
                             onUpdatePerforming listener: @escaping Listener) -> Bool {
        stopListening()

        mutableState.write { state in
            state.listenerQueue = queue
            state.listener = listener
        }

        let weakManager = WeakManager(manager: self)

        var context = SCNetworkReachabilityContext(
            version: 0,
            info: Unmanaged.passUnretained(weakManager).toOpaque(),
            retain: { info in
                let unmanaged = Unmanaged<WeakManager>.fromOpaque(info)
                _ = unmanaged.retain()

                return UnsafeRawPointer(unmanaged.toOpaque())
            },
            release: { info in
                let unmanaged = Unmanaged<WeakManager>.fromOpaque(info)
                unmanaged.release()
            },
            copyDescription: { info in
                let unmanaged = Unmanaged<WeakManager>.fromOpaque(info)
                let weakManager = unmanaged.takeUnretainedValue()
                let description = weakManager.manager?.flags?.readableDescription ?? "nil"

                return Unmanaged.passRetained(description as CFString)
            }
        )
        let callback: SCNetworkReachabilityCallBack = { _, flags, info in
            guard let info else { return }

            let weakManager = Unmanaged<WeakManager>.fromOpaque(info).takeUnretainedValue()
            weakManager.manager?.notifyListener(flags)
        }

        let queueAdded = SCNetworkReachabilitySetDispatchQueue(reachability, reachabilityQueue)
        let callbackAdded = SCNetworkReachabilitySetCallback(reachability, callback, &context)

        if let currentFlags = flags {
            reachabilityQueue.async {
                self.notifyListener(currentFlags)
            }
        }

        return callbackAdded && queueAdded
    }

    open func stopListening() {
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachability, nil)
        mutableState.write { state in
            state.listener = nil
            state.listenerQueue = nil
            state.previousStatus = nil
        }
    }

    func notifyListener(_ flags: SCNetworkReachabilityFlags) {
        let newStatus = NetworkReachabilityStatus(flags)

        mutableState.write { [newStatus] state in
            guard state.previousStatus != newStatus else { return }

            state.previousStatus = newStatus

            let listener = state.listener
            state.listenerQueue?.async { listener?(newStatus) }
        }
    }

    private final class WeakManager {
        weak var manager: NetworkReachabilityManager?

        init(manager: NetworkReachabilityManager?) {
            self.manager = manager
        }
    }
}

extension SCNetworkReachabilityFlags {
    var isReachable: Bool { contains(.reachable) }
    var isConnectionRequired: Bool { contains(.connectionRequired) }
    var canConnectAutomatically: Bool { contains(.connectionOnDemand) || contains(.connectionOnTraffic) }
    var canConnectWithoutUserInteraction: Bool { canConnectAutomatically && !contains(.interventionRequired) }
    var isActuallyReachable: Bool { isReachable && (!isConnectionRequired || canConnectWithoutUserInteraction) }
    var isCellular: Bool {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return contains(.isWWAN)
        #else
        return false
        #endif
    }

    var readableDescription: String {
        let W = isCellular ? "W" : "-"
        let R = isReachable ? "R" : "-"
        let c = isConnectionRequired ? "c" : "-"
        let t = contains(.transientConnection) ? "t" : "-"
        let i = contains(.interventionRequired) ? "i" : "-"
        let C = contains(.connectionOnTraffic) ? "C" : "-"
        let D = contains(.connectionOnDemand) ? "D" : "-"
        let l = contains(.isLocalAddress) ? "l" : "-"
        let d = contains(.isDirect) ? "d" : "-"
        let a = contains(.connectionAutomatic) ? "a" : "-"

        return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)\(a)"
    }
}
#endif
