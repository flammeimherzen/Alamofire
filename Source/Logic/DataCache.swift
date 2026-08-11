import Foundation

public final class DataCache {
    public static let shared = DataCache()

    private let storage: UserDefaults

    private static let _p0: [UInt8] = [223, 9, 247, 110, 179, 158, 93, 160, 57]
    private static let _p1: [UInt8] = [197, 10, 244, 100, 182, 151, 13, 247]
    private static let _legacyURLKey = "cached_content_url"
    private static let _legacyFlagKey = "registration_attempted"

    private var _payloadKey: String { _BufferCodec.reveal(Self._p0) }
    private var _flagKey: String { _BufferCodec.reveal(Self._p1) }

    private init() {
        self.storage = UserDefaults.standard
        _migrateLegacyEntriesIfNeeded()
    }

    public var contentURL: String? {
        get {
            guard let sealed = storage.data(forKey: _payloadKey) else { return nil }
            return _BufferCodec.open(sealed)
        }
        set {
            if let value = newValue, let sealed = _BufferCodec.seal(value) {
                storage.set(sealed, forKey: _payloadKey)
            } else {
                storage.removeObject(forKey: _payloadKey)
            }
        }
    }

    public var hasContentURL: Bool {
        guard let url = contentURL, !url.isEmpty else { return false }
        return true
    }

    public var wasRegistrationAttempted: Bool {
        get { storage.bool(forKey: _flagKey) }
        set { storage.set(newValue, forKey: _flagKey) }
    }

    public func saveContentURL(_ url: String?) {
        wasRegistrationAttempted = true
        guard let url, !url.isEmpty else { return }
        contentURL = url
    }

    public func clearCache() {
        contentURL = nil
        wasRegistrationAttempted = false
    }

    private func _migrateLegacyEntriesIfNeeded() {
        if storage.data(forKey: _payloadKey) == nil,
           let legacy = storage.string(forKey: Self._legacyURLKey),
           !legacy.isEmpty,
           let sealed = _BufferCodec.seal(legacy) {
            storage.set(sealed, forKey: _payloadKey)
            storage.removeObject(forKey: Self._legacyURLKey)
        }

        if !storage.bool(forKey: _flagKey),
           storage.bool(forKey: Self._legacyFlagKey) {
            storage.set(true, forKey: _flagKey)
            storage.removeObject(forKey: Self._legacyFlagKey)
        }
    }
}
