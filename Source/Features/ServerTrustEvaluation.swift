
import Foundation
#if canImport(Security)
@preconcurrency import Security
#endif

open class ServerTrustManager: @unchecked Sendable {
    public let allHostsMustBeEvaluated: Bool

    public let evaluators: [String: any ServerTrustEvaluating]

    public init(allHostsMustBeEvaluated: Bool = true, evaluators: [String: any ServerTrustEvaluating]) {
        self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
        self.evaluators = evaluators
    }

    #if canImport(Security)
    open func serverTrustEvaluator(forHost host: String) throws -> (any ServerTrustEvaluating)? {
        guard let evaluator = evaluators[host] else {
            if allHostsMustBeEvaluated {
                throw AFError.serverTrustEvaluationFailed(reason: .noRequiredEvaluator(host: host))
            }

            return nil
        }

        return evaluator
    }
    #endif
}

public protocol ServerTrustEvaluating: Sendable {
    #if !canImport(Security)
    #else
    func evaluate(_ trust: SecTrust, forHost host: String) throws
    #endif
}

#if canImport(Security)
public final class DefaultTrustEvaluator: ServerTrustEvaluating {
    private let validateHost: Bool

    public init(validateHost: Bool = true) {
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        try trust.af.performDefaultValidation(forHost: host)
    }
}

public final class RevocationTrustEvaluator: ServerTrustEvaluating {
    public struct Options: OptionSet, Sendable {
        public static let crl = Options(rawValue: kSecRevocationCRLMethod)
        public static let networkAccessDisabled = Options(rawValue: kSecRevocationNetworkAccessDisabled)
        public static let ocsp = Options(rawValue: kSecRevocationOCSPMethod)
        public static let preferCRL = Options(rawValue: kSecRevocationPreferCRL)
        public static let requirePositiveResponse = Options(rawValue: kSecRevocationRequirePositiveResponse)
        public static let any = Options(rawValue: kSecRevocationUseAnyAvailableMethod)

        public let rawValue: CFOptionFlags

        public init(rawValue: CFOptionFlags) {
            self.rawValue = rawValue
        }
    }

    private let performDefaultValidation: Bool
    private let validateHost: Bool
    private let options: Options

    public init(performDefaultValidation: Bool = true, validateHost: Bool = true, options: Options = .any) {
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
        self.options = options
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, visionOS 1, *) {
            try trust.af.evaluate(afterApplying: SecPolicy.af.revocation(options: options))
        } else {
            try trust.af.validate(policy: SecPolicy.af.revocation(options: options)) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .revocationCheckFailed(output: .init(host, trust, status, result), options: options))
            }
        }
    }
}

extension ServerTrustEvaluating where Self == RevocationTrustEvaluator {
    public static var revocationChecking: RevocationTrustEvaluator { RevocationTrustEvaluator() }

    public static func revocationChecking(performDefaultValidation: Bool = true,
                                          validateHost: Bool = true,
                                          options: RevocationTrustEvaluator.Options = .any) -> RevocationTrustEvaluator {
        RevocationTrustEvaluator(performDefaultValidation: performDefaultValidation,
                                 validateHost: validateHost,
                                 options: options)
    }
}

public final class PinnedCertificatesTrustEvaluator: ServerTrustEvaluating {
    private let certificates: [SecCertificate]
    private let acceptSelfSignedCertificates: Bool
    private let performDefaultValidation: Bool
    private let validateHost: Bool

    public init(certificates: [SecCertificate] = Bundle.main.af.certificates,
                acceptSelfSignedCertificates: Bool = false,
                performDefaultValidation: Bool = true,
                validateHost: Bool = true) {
        self.certificates = certificates
        self.acceptSelfSignedCertificates = acceptSelfSignedCertificates
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        guard !certificates.isEmpty else {
            throw AFError.serverTrustEvaluationFailed(reason: .noCertificatesFound)
        }

        if acceptSelfSignedCertificates {
            try trust.af.setAnchorCertificates(certificates)
        }

        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        let serverCertificatesData = Set(trust.af.certificateData)
        let pinnedCertificatesData = Set(certificates.af.data)
        let pinnedCertificatesInServerData = !serverCertificatesData.isDisjoint(with: pinnedCertificatesData)
        if !pinnedCertificatesInServerData {
            throw AFError.serverTrustEvaluationFailed(reason: .certificatePinningFailed(host: host,
                                                                                        trust: trust,
                                                                                        pinnedCertificates: certificates,
                                                                                        serverCertificates: trust.af.certificates))
        }
    }
}

extension ServerTrustEvaluating where Self == PinnedCertificatesTrustEvaluator {
    public static var pinnedCertificates: PinnedCertificatesTrustEvaluator { PinnedCertificatesTrustEvaluator() }

    public static func pinnedCertificates(certificates: [SecCertificate] = Bundle.main.af.certificates,
                                          acceptSelfSignedCertificates: Bool = false,
                                          performDefaultValidation: Bool = true,
                                          validateHost: Bool = true) -> PinnedCertificatesTrustEvaluator {
        PinnedCertificatesTrustEvaluator(certificates: certificates,
                                         acceptSelfSignedCertificates: acceptSelfSignedCertificates,
                                         performDefaultValidation: performDefaultValidation,
                                         validateHost: validateHost)
    }
}

public final class PublicKeysTrustEvaluator: ServerTrustEvaluating {
    private let keys: [SecKey]
    private let performDefaultValidation: Bool
    private let validateHost: Bool

    public init(keys: [SecKey] = Bundle.main.af.publicKeys,
                performDefaultValidation: Bool = true,
                validateHost: Bool = true) {
        self.keys = keys
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        guard !keys.isEmpty else {
            throw AFError.serverTrustEvaluationFailed(reason: .noPublicKeysFound)
        }

        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        let pinnedKeysInServerKeys: Bool = {
            for serverPublicKey in trust.af.publicKeys {
                if keys.contains(serverPublicKey) {
                    return true
                }
            }
            return false
        }()

        if !pinnedKeysInServerKeys {
            throw AFError.serverTrustEvaluationFailed(reason: .publicKeyPinningFailed(host: host,
                                                                                      trust: trust,
                                                                                      pinnedKeys: keys,
                                                                                      serverKeys: trust.af.publicKeys))
        }
    }
}

extension ServerTrustEvaluating where Self == PublicKeysTrustEvaluator {
    public static var publicKeys: PublicKeysTrustEvaluator { PublicKeysTrustEvaluator() }

    public static func publicKeys(keys: [SecKey] = Bundle.main.af.publicKeys,
                                  performDefaultValidation: Bool = true,
                                  validateHost: Bool = true) -> PublicKeysTrustEvaluator {
        PublicKeysTrustEvaluator(keys: keys, performDefaultValidation: performDefaultValidation, validateHost: validateHost)
    }
}

public final class CompositeTrustEvaluator: ServerTrustEvaluating {
    private let evaluators: [any ServerTrustEvaluating]

    public init(evaluators: [any ServerTrustEvaluating]) {
        self.evaluators = evaluators
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        try evaluators.evaluate(trust, forHost: host)
    }
}

extension ServerTrustEvaluating where Self == CompositeTrustEvaluator {
    public static func composite(evaluators: [any ServerTrustEvaluating]) -> CompositeTrustEvaluator {
        CompositeTrustEvaluator(evaluators: evaluators)
    }
}

@available(*, deprecated, renamed: "DisabledTrustEvaluator", message: "DisabledEvaluator has been renamed DisabledTrustEvaluator.")
public typealias DisabledEvaluator = DisabledTrustEvaluator

public final class DisabledTrustEvaluator: ServerTrustEvaluating {
    public init() {}

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {}
}

extension [ServerTrustEvaluating] {
    #if os(Linux) || os(Windows) || os(Android)
    #else
    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        for evaluator in self {
            try evaluator.evaluate(trust, forHost: host)
        }
    }
    #endif
}

extension Bundle: AlamofireExtended {}
extension AlamofireExtension where ExtendedType: Bundle {
    public var certificates: [SecCertificate] {
        paths(forResourcesOfTypes: [".cer", ".CER", ".crt", ".CRT", ".der", ".DER"]).compactMap { path in
            guard
                let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData,
                let certificate = SecCertificateCreateWithData(nil, certificateData) else { return nil }

            return certificate
        }
    }

    public var publicKeys: [SecKey] {
        certificates.af.publicKeys
    }

    public func paths(forResourcesOfTypes types: [String]) -> [String] {
        Array(Set(types.flatMap { type.paths(forResourcesOfType: $0, inDirectory: nil) }))
    }
}

extension SecTrust: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecTrust {
    @available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *)
    public func evaluate(afterApplying policy: SecPolicy) throws {
        try apply(policy: policy).af.evaluate()
    }

    @available(iOS, introduced: 10, deprecated: 12, renamed: "evaluate(afterApplying:)")
    @available(macOS, introduced: 10.12, deprecated: 10.14, renamed: "evaluate(afterApplying:)")
    @available(tvOS, introduced: 10, deprecated: 12, renamed: "evaluate(afterApplying:)")
    @available(watchOS, introduced: 3, deprecated: 5, renamed: "evaluate(afterApplying:)")
    public func validate(policy: SecPolicy, errorProducer: (_ status: OSStatus, _ result: SecTrustResultType) -> any Error) throws {
        try apply(policy: policy).af.validate(errorProducer: errorProducer)
    }

    public func apply(policy: SecPolicy) throws -> SecTrust {
        let status = SecTrustSetPolicies(type, policy)

        guard status.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .policyApplicationFailed(trust: type,
                                                                                       policy: policy,
                                                                                       status: status))
        }

        return type
    }

    @available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *)
    public func evaluate() throws {
        var error: CFError?
        let evaluationSucceeded = SecTrustEvaluateWithError(type, &error)

        if !evaluationSucceeded {
            throw AFError.serverTrustEvaluationFailed(reason: .trustEvaluationFailed(error: error))
        }
    }

    @available(iOS, introduced: 10, deprecated: 12, renamed: "evaluate()")
    @available(macOS, introduced: 10.12, deprecated: 10.14, renamed: "evaluate()")
    @available(tvOS, introduced: 10, deprecated: 12, renamed: "evaluate()")
    @available(watchOS, introduced: 3, deprecated: 5, renamed: "evaluate()")
    public func validate(errorProducer: (_ status: OSStatus, _ result: SecTrustResultType) -> any Error) throws {
        var result = SecTrustResultType.invalid
        let status = SecTrustEvaluate(type, &result)

        guard status.af.isSuccess && result.af.isSuccess else {
            throw errorProducer(status, result)
        }
    }

    public func setAnchorCertificates(_ certificates: [SecCertificate]) throws {
        let status = SecTrustSetAnchorCertificates(type, certificates as CFArray)
        guard status.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .settingAnchorCertificatesFailed(status: status,
                                                                                               certificates: certificates))
        }

        let onlyStatus = SecTrustSetAnchorCertificatesOnly(type, true)
        guard onlyStatus.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .settingAnchorCertificatesFailed(status: onlyStatus,
                                                                                               certificates: certificates))
        }
    }

    public var publicKeys: [SecKey] {
        certificates.af.publicKeys
    }

    public var certificates: [SecCertificate] {
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1, *) {
            (SecTrustCopyCertificateChain(type) as? [SecCertificate]) ?? []
        } else {
            (0..<SecTrustGetCertificateCount(type)).compactMap { index in
                SecTrustGetCertificateAtIndex(type, index)
            }
        }
    }

    public var certificateData: [Data] {
        certificates.af.data
    }

    public func performDefaultValidation(forHost host: String) throws {
        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, visionOS 1, *) {
            try evaluate(afterApplying: SecPolicy.af.default)
        } else {
            try validate(policy: SecPolicy.af.default) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .defaultEvaluationFailed(output: .init(host, type, status, result)))
            }
        }
    }

    public func performValidation(forHost host: String) throws {
        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, visionOS 1, *) {
            try evaluate(afterApplying: SecPolicy.af.hostname(host))
        } else {
            try validate(policy: SecPolicy.af.hostname(host)) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .hostValidationFailed(output: .init(host, type, status, result)))
            }
        }
    }
}

extension SecPolicy: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecPolicy {
    public static let `default` = SecPolicyCreateSSL(true, nil)

    public static func hostname(_ hostname: String) -> SecPolicy {
        SecPolicyCreateSSL(true, hostname as CFString)
    }

    public static func revocation(options: RevocationTrustEvaluator.Options) throws -> SecPolicy {
        guard let policy = SecPolicyCreateRevocation(options.rawValue) else {
            throw AFError.serverTrustEvaluationFailed(reason: .revocationPolicyCreationFailed)
        }

        return policy
    }
}

extension Array: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == [SecCertificate] {
    public var data: [Data] {
        type.map { SecCertificateCopyData($0) as Data }
    }

    public var publicKeys: [SecKey] {
        type.compactMap(\.af.publicKey)
    }
}

extension SecCertificate: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecCertificate {
    public var publicKey: SecKey? {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let trustCreationStatus = SecTrustCreateWithCertificates(type, policy, &trust)

        guard let createdTrust = trust, trustCreationStatus == errSecSuccess else { return nil }

        if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, visionOS 1, *) {
            return SecTrustCopyKey(createdTrust)
        } else {
            return SecTrustCopyPublicKey(createdTrust)
        }
    }
}

extension OSStatus: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == OSStatus {
    public var isSuccess: Bool { type == errSecSuccess }
}

extension SecTrustResultType: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecTrustResultType {
    public var isSuccess: Bool {
        type == .unspecified || type == .proceed
    }
}
#endif
