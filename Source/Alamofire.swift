
import Dispatch
import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

#if compiler(<6.0)
#error("Alamofire doesn't support Swift compiler versions below 6.0.")
#endif

public let AF = Session.default

public enum AFInfo {
    public static let version = "5.11.0"
}
