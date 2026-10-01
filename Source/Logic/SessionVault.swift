import Foundation

/// The gate identifies a returning install by the session cookie on
/// `POST /register`. That cookie is a session cookie, so URLSession drops it
/// when the process dies and the next launch looks like a new user.
enum SessionVault {
    private static let _key: [UInt8] = [198, 88, 191, 52, 166, 211, 78, 191, 54, 179, 213, 16, 231, 109]
    private static let lifetime: TimeInterval = 60 * 60 * 24 * 400
    private static let lock = NSLock()

    static func restore() {
        lock.lock()
        defer { lock.unlock() }
        guard let sealed = UserDefaults.standard.data(forKey: _BufferCodec.reveal(_key)),
              let opened = _BufferCodec.open(sealed),
              let archived = Data(base64Encoded: opened),
              let cookies = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, HTTPCookie.self],
                from: archived
              ) as? [HTTPCookie]
        else { return }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func persist() {
        lock.lock()
        defer { lock.unlock() }
        let durable = (HTTPCookieStorage.shared.cookies ?? []).compactMap(durableCookie)
        guard !durable.isEmpty,
              let archived = try? NSKeyedArchiver.archivedData(withRootObject: durable, requiringSecureCoding: true),
              let sealed = _BufferCodec.seal(archived.base64EncodedString())
        else { return }
        for cookie in durable {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        UserDefaults.standard.set(sealed, forKey: _BufferCodec.reveal(_key))
    }

    static func store(response: HTTPURLResponse?) {
        guard let response, let url = response.url else { return }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let header = value as? String else { continue }
            headers[name] = header
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private static func durableCookie(_ cookie: HTTPCookie) -> HTTPCookie? {
        guard var props = cookie.properties else { return cookie }
        if cookie.expiresDate == nil || cookie.isSessionOnly {
            props.removeValue(forKey: .discard)
            props[.expires] = Date().addingTimeInterval(lifetime)
        }
        return HTTPCookie(properties: props) ?? cookie
    }
}

final class RegistrationGate {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    private var result: (DisplayMode, String?)?
    private var waiters: [(DisplayMode, String?) -> Void] = []

    /// `true` only for the first caller in this process. Later callers share that result.
    func begin(_ completion: @escaping (DisplayMode, String?) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let result, finished {
            let replay = result
            DispatchQueue.main.async { completion(replay.0, replay.1) }
            return false
        }
        waiters.append(completion)
        if started { return false }
        started = true
        return true
    }

    func finish(_ mode: DisplayMode, _ url: String?) {
        lock.lock()
        finished = true
        result = (mode, url)
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter(mode, url)
        }
    }
}
