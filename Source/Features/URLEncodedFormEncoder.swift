
import Foundation

public final class URLEncodedFormEncoder {
    public enum ArrayEncoding {
        case brackets
        case noBrackets
        case indexInBrackets
        case custom((_ key: String, _ index: Int) -> String)

        func encode(_ key: String, atIndex index: Int) -> String {
            switch self {
            case .brackets: "\(key)[]"
            case .noBrackets: key
            case .indexInBrackets: "\(key)[\(index)]"
            case let .custom(encoding): encoding(key, index)
            }
        }
    }

    public enum BoolEncoding {
        case numeric
        case literal

        func encode(_ value: Bool) -> String {
            switch self {
            case .numeric: value ? "1" : "0"
            case .literal: value ? "true" : "false"
            }
        }
    }

    public enum DataEncoding {
        case deferredToData
        case base64
        case custom((Data) throws -> String)

        func encode(_ data: Data) throws -> String? {
            switch self {
            case .deferredToData: nil
            case .base64: data.base64EncodedString()
            case let .custom(encoding): try encoding(data)
            }
        }
    }

    public enum DateEncoding {
        private static let iso8601Formatter = Protected<ISO8601DateFormatter>({
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = .withInternetDateTime
            return formatter
        }())

        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
        case formatted(DateFormatter)
        case custom((Date) throws -> String)

        func encode(_ date: Date) throws -> String? {
            switch self {
            case .deferredToDate:
                nil
            case .secondsSince1970:
                String(date.timeIntervalSince1970)
            case .millisecondsSince1970:
                String(date.timeIntervalSince1970 * 1000.0)
            case .iso8601:
                DateEncoding.iso8601Formatter.read { $0.string(from: date) }
            case let .formatted(formatter):
                formatter.string(from: date)
            case let .custom(closure):
                try closure(date)
            }
        }
    }

    public enum KeyEncoding {
        case useDefaultKeys
        case convertToSnakeCase
        case convertToKebabCase
        case capitalized
        case uppercased
        case lowercased
        case custom((String) -> String)

        func encode(_ key: String) -> String {
            switch self {
            case .useDefaultKeys: key
            case .convertToSnakeCase: convertToSnakeCase(key)
            case .convertToKebabCase: convertToKebabCase(key)
            case .capitalized: String(key.prefix(1).uppercased() + key.dropFirst())
            case .uppercased: key.uppercased()
            case .lowercased: key.lowercased()
            case let .custom(encoding): encoding(key)
            }
        }

        private func convertToSnakeCase(_ key: String) -> String {
            convert(key, usingSeparator: "_")
        }

        private func convertToKebabCase(_ key: String) -> String {
            convert(key, usingSeparator: "-")
        }

        private func convert(_ key: String, usingSeparator separator: String) -> String {
            guard !key.isEmpty else { return key }

            var words: [Range<String.Index>] = []
            var wordStart = key.startIndex
            var searchRange = key.index(after: wordStart)..<key.endIndex

            while let upperCaseRange = key.rangeOfCharacter(from: .uppercaseLetters, options: [], range: searchRange) {
                let untilUpperCase = wordStart..<upperCaseRange.lowerBound
                words.append(untilUpperCase)

                searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
                guard let lowerCaseRange = key.rangeOfCharacter(from: .lowercaseLetters, options: [], range: searchRange) else {
                    wordStart = searchRange.lowerBound
                    break
                }

                let nextCharacterAfterCapital = key.index(after: upperCaseRange.lowerBound)
                if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                    wordStart = upperCaseRange.lowerBound
                } else {
                    let beforeLowerIndex = key.index(before: lowerCaseRange.lowerBound)
                    words.append(upperCaseRange.lowerBound..<beforeLowerIndex)

                    wordStart = beforeLowerIndex
                }
                searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
            }
            words.append(wordStart..<searchRange.upperBound)
            let result = words.map { range in
                key[range].lowercased()
            }.joined(separator: separator)

            return result
        }
    }

    public struct KeyPathEncoding: Sendable {
        public static let brackets = KeyPathEncoding { "[\($0)]" }
        public static let dots = KeyPathEncoding { ".\($0)" }

        private let encoding: @Sendable (_ subkey: String) -> String

        public init(encoding: @escaping @Sendable (_ subkey: String) -> String) {
            self.encoding = encoding
        }

        func encodeKeyPath(_ keyPath: String) -> String {
            encoding(keyPath)
        }
    }

    public struct NilEncoding: Sendable {
        public static let dropKey = NilEncoding { nil }
        public static let dropValue = NilEncoding { "" }
        public static let null = NilEncoding { "null" }

        private let encoding: @Sendable () -> String?

        public init(encoding: @escaping @Sendable () -> String?) {
            self.encoding = encoding
        }

        func encodeNil() -> String? {
            encoding()
        }
    }

    public enum SpaceEncoding {
        case percentEscaped
        case plusReplaced

        func encode(_ string: String) -> String {
            switch self {
            case .percentEscaped: string.replacingOccurrences(of: " ", with: "%20")
            case .plusReplaced: string.replacingOccurrences(of: " ", with: "+")
            }
        }
    }

    public enum Error: Swift.Error {
        case invalidRootObject(String)

        var localizedDescription: String {
            switch self {
            case let .invalidRootObject(object):
                "URLEncodedFormEncoder requires keyed root object. Received \(object) instead."
            }
        }
    }

    public let alphabetizeKeyValuePairs: Bool
    public let arrayEncoding: ArrayEncoding
    public let boolEncoding: BoolEncoding
    public let dataEncoding: DataEncoding
    public let dateEncoding: DateEncoding
    public let keyEncoding: KeyEncoding
    public let keyPathEncoding: KeyPathEncoding
    public let nilEncoding: NilEncoding
    public let spaceEncoding: SpaceEncoding
    public var allowedCharacters: CharacterSet

    public init(alphabetizeKeyValuePairs: Bool = true,
                arrayEncoding: ArrayEncoding = .brackets,
                boolEncoding: BoolEncoding = .numeric,
                dataEncoding: DataEncoding = .base64,
                dateEncoding: DateEncoding = .deferredToDate,
                keyEncoding: KeyEncoding = .useDefaultKeys,
                keyPathEncoding: KeyPathEncoding = .brackets,
                nilEncoding: NilEncoding = .dropKey,
                spaceEncoding: SpaceEncoding = .percentEscaped,
                allowedCharacters: CharacterSet = .afURLQueryAllowed) {
        self.alphabetizeKeyValuePairs = alphabetizeKeyValuePairs
        self.arrayEncoding = arrayEncoding
        self.boolEncoding = boolEncoding
        self.dataEncoding = dataEncoding
        self.dateEncoding = dateEncoding
        self.keyEncoding = keyEncoding
        self.keyPathEncoding = keyPathEncoding
        self.nilEncoding = nilEncoding
        self.spaceEncoding = spaceEncoding
        self.allowedCharacters = allowedCharacters
    }

    func encode(_ value: any Encodable) throws -> URLEncodedFormComponent {
        let context = URLEncodedFormContext(.object([]))
        let encoder = _URLEncodedFormEncoder(context: context,
                                             boolEncoding: boolEncoding,
                                             dataEncoding: dataEncoding,
                                             dateEncoding: dateEncoding,
                                             nilEncoding: nilEncoding)
        try value.encode(to: encoder)

        return context.component
    }

    public func encode(_ value: any Encodable) throws -> String {
        let component: URLEncodedFormComponent = try encode(value)

        guard case let .object(object) = component else {
            throw Error.invalidRootObject("\(component)")
        }

        let serializer = URLEncodedFormSerializer(alphabetizeKeyValuePairs: alphabetizeKeyValuePairs,
                                                  arrayEncoding: arrayEncoding,
                                                  keyEncoding: keyEncoding,
                                                  keyPathEncoding: keyPathEncoding,
                                                  spaceEncoding: spaceEncoding,
                                                  allowedCharacters: allowedCharacters)
        let query = serializer.serialize(object)

        return query
    }

    public func encode(_ value: any Encodable) throws -> Data {
        let string: String = try encode(value)

        return Data(string.utf8)
    }
}

final class _URLEncodedFormEncoder {
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    let context: URLEncodedFormContext

    private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
    private let dataEncoding: URLEncodedFormEncoder.DataEncoding
    private let dateEncoding: URLEncodedFormEncoder.DateEncoding
    private let nilEncoding: URLEncodedFormEncoder.NilEncoding

    init(context: URLEncodedFormContext,
         codingPath: [any CodingKey] = [],
         boolEncoding: URLEncodedFormEncoder.BoolEncoding,
         dataEncoding: URLEncodedFormEncoder.DataEncoding,
         dateEncoding: URLEncodedFormEncoder.DateEncoding,
         nilEncoding: URLEncodedFormEncoder.NilEncoding) {
        self.context = context
        self.codingPath = codingPath
        self.boolEncoding = boolEncoding
        self.dataEncoding = dataEncoding
        self.dateEncoding = dateEncoding
        self.nilEncoding = nilEncoding
    }
}

extension _URLEncodedFormEncoder: Encoder {
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = _URLEncodedFormEncoder.KeyedContainer<Key>(context: context,
                                                                   codingPath: codingPath,
                                                                   boolEncoding: boolEncoding,
                                                                   dataEncoding: dataEncoding,
                                                                   dateEncoding: dateEncoding,
                                                                   nilEncoding: nilEncoding)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                codingPath: codingPath,
                                                boolEncoding: boolEncoding,
                                                dataEncoding: dataEncoding,
                                                dateEncoding: dateEncoding,
                                                nilEncoding: nilEncoding)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                    codingPath: codingPath,
                                                    boolEncoding: boolEncoding,
                                                    dataEncoding: dataEncoding,
                                                    dateEncoding: dateEncoding,
                                                    nilEncoding: nilEncoding)
    }
}

final class URLEncodedFormContext {
    var component: URLEncodedFormComponent

    init(_ component: URLEncodedFormComponent) {
        self.component = component
    }
}

enum URLEncodedFormComponent {
    typealias Object = [(key: String, value: URLEncodedFormComponent)]

    case string(String)
    case array([URLEncodedFormComponent])
    case object(Object)

    var array: [URLEncodedFormComponent]? {
        switch self {
        case let .array(array): array
        default: nil
        }
    }

    var object: Object? {
        switch self {
        case let .object(object): object
        default: nil
        }
    }

    mutating func set(to value: URLEncodedFormComponent, at path: [any CodingKey]) {
        set(&self, to: value, at: path)
    }

    private func set(_ context: inout URLEncodedFormComponent, to value: URLEncodedFormComponent, at path: [any CodingKey]) {
        guard !path.isEmpty else {
            context = value
            return
        }

        let end = path[0]
        var child: URLEncodedFormComponent
        switch path.count {
        case 1:
            child = value
        case 2...:
            if let index = end.intValue {
                let array = context.array ?? []
                if array.count > index {
                    child = array[index]
                } else {
                    child = .array([])
                }
                set(&child, to: value, at: Array(path[1...]))
            } else {
                child = context.object?.first { $0.key == end.stringValue }?.value ?? .object(.init())
                set(&child, to: value, at: Array(path[1...]))
            }
        default: fatalError("Unreachable")
        }

        if let index = end.intValue {
            if var array = context.array {
                if array.count > index {
                    array[index] = child
                } else {
                    array.append(child)
                }
                context = .array(array)
            } else {
                context = .array([child])
            }
        } else {
            if var object = context.object {
                if let index = object.firstIndex(where: { $0.key == end.stringValue }) {
                    object[index] = (key: end.stringValue, value: child)
                } else {
                    object.append((key: end.stringValue, value: child))
                }
                context = .object(object)
            } else {
                context = .object([(key: end.stringValue, value: child)])
            }
        }
    }
}

struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init<Key>(_ base: Key) where Key: CodingKey {
        if let intValue = base.intValue {
            self.init(intValue: intValue)!
        } else {
            self.init(stringValue: base.stringValue)!
        }
    }
}

extension _URLEncodedFormEncoder {
    final class KeyedContainer<Key> where Key: CodingKey {
        var codingPath: [any CodingKey]

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding
        private let nilEncoding: URLEncodedFormEncoder.NilEncoding

        init(context: URLEncodedFormContext,
             codingPath: [any CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding,
             nilEncoding: URLEncodedFormEncoder.NilEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
            self.nilEncoding = nilEncoding
        }

        private func nestedCodingPath(for key: any CodingKey) -> [any CodingKey] {
            codingPath + [key]
        }
    }
}

extension _URLEncodedFormEncoder.KeyedContainer: KeyedEncodingContainerProtocol {
    func encodeNil(forKey key: Key) throws {
        guard let nilValue = nilEncoding.encodeNil() else { return }

        try encode(nilValue, forKey: key)
    }

    func encodeIfPresent(_ value: Bool?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: String?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Double?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Float?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Int?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Int8?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Int16?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Int32?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: Int64?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: UInt?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws {
        try _encodeIfPresent(value, forKey: key)
    }

    func encodeIfPresent<Value>(_ value: Value?, forKey key: Key) throws where Value: Encodable {
        try _encodeIfPresent(value, forKey: key)
    }

    func _encodeIfPresent<Value>(_ value: Value?, forKey key: Key) throws where Value: Encodable {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        var container = nestedSingleValueEncoder(for: key)
        try container.encode(value)
    }

    func nestedSingleValueEncoder(for key: Key) -> any SingleValueEncodingContainer {
        let container = _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                                    codingPath: nestedCodingPath(for: key),
                                                                    boolEncoding: boolEncoding,
                                                                    dataEncoding: dataEncoding,
                                                                    dateEncoding: dateEncoding,
                                                                    nilEncoding: nilEncoding)

        return container
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let container = _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                                codingPath: nestedCodingPath(for: key),
                                                                boolEncoding: boolEncoding,
                                                                dataEncoding: dataEncoding,
                                                                dateEncoding: dateEncoding,
                                                                nilEncoding: nilEncoding)

        return container
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let container = _URLEncodedFormEncoder.KeyedContainer<NestedKey>(context: context,
                                                                         codingPath: nestedCodingPath(for: key),
                                                                         boolEncoding: boolEncoding,
                                                                         dataEncoding: dataEncoding,
                                                                         dateEncoding: dateEncoding,
                                                                         nilEncoding: nilEncoding)

        return KeyedEncodingContainer(container)
    }

    func superEncoder() -> any Encoder {
        _URLEncodedFormEncoder(context: context,
                               codingPath: codingPath,
                               boolEncoding: boolEncoding,
                               dataEncoding: dataEncoding,
                               dateEncoding: dateEncoding,
                               nilEncoding: nilEncoding)
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        _URLEncodedFormEncoder(context: context,
                               codingPath: nestedCodingPath(for: key),
                               boolEncoding: boolEncoding,
                               dataEncoding: dataEncoding,
                               dateEncoding: dateEncoding,
                               nilEncoding: nilEncoding)
    }
}

extension _URLEncodedFormEncoder {
    final class SingleValueContainer {
        var codingPath: [any CodingKey]

        private var canEncodeNewValue = true

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding
        private let nilEncoding: URLEncodedFormEncoder.NilEncoding

        init(context: URLEncodedFormContext,
             codingPath: [any CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding,
             nilEncoding: URLEncodedFormEncoder.NilEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
            self.nilEncoding = nilEncoding
        }

        private func checkCanEncode(value: Any?) throws {
            guard canEncodeNewValue else {
                let context = EncodingError.Context(codingPath: codingPath,
                                                    debugDescription: "Attempt to encode value through single value container when previously value already encoded.")
                throw EncodingError.invalidValue(value as Any, context)
            }
        }
    }
}

extension _URLEncodedFormEncoder.SingleValueContainer: SingleValueEncodingContainer {
    func encodeNil() throws {
        guard let nilValue = nilEncoding.encodeNil() else { return }

        try encode(nilValue)
    }

    func encode(_ value: Bool) throws {
        try encode(value, as: String(boolEncoding.encode(value)))
    }

    func encode(_ value: String) throws {
        try encode(value, as: value)
    }

    func encode(_ value: Double) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Float) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int8) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int16) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int32) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int64) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt8) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt16) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt32) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt64) throws {
        try encode(value, as: String(value))
    }

    private func encode<T>(_ value: T, as string: String) throws where T: Encodable {
        try checkCanEncode(value: value)
        defer { canEncodeNewValue = false }

        context.component.set(to: .string(string), at: codingPath)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let date as Date:
            guard let string = try dateEncoding.encode(date) else {
                try attemptToEncode(value)
                return
            }

            try encode(value, as: string)
        case let data as Data:
            guard let string = try dataEncoding.encode(data) else {
                try attemptToEncode(value)
                return
            }

            try encode(value, as: string)
        case let decimal as Decimal:
            try encode(value, as: String(describing: decimal))
        default:
            try attemptToEncode(value)
        }
    }

    private func attemptToEncode<T>(_ value: T) throws where T: Encodable {
        try checkCanEncode(value: value)
        defer { canEncodeNewValue = false }

        let encoder = _URLEncodedFormEncoder(context: context,
                                             codingPath: codingPath,
                                             boolEncoding: boolEncoding,
                                             dataEncoding: dataEncoding,
                                             dateEncoding: dateEncoding,
                                             nilEncoding: nilEncoding)
        try value.encode(to: encoder)
    }
}

extension _URLEncodedFormEncoder {
    final class UnkeyedContainer {
        var codingPath: [any CodingKey]

        var count = 0
        var nestedCodingPath: [any CodingKey] {
            codingPath + [AnyCodingKey(intValue: count)!]
        }

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding
        private let nilEncoding: URLEncodedFormEncoder.NilEncoding

        init(context: URLEncodedFormContext,
             codingPath: [any CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding,
             nilEncoding: URLEncodedFormEncoder.NilEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
            self.nilEncoding = nilEncoding
        }
    }
}

extension _URLEncodedFormEncoder.UnkeyedContainer: UnkeyedEncodingContainer {
    func encodeNil() throws {
        guard let nilValue = nilEncoding.encodeNil() else { return }

        try encode(nilValue)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        var container = nestedSingleValueContainer()
        try container.encode(value)
    }

    func nestedSingleValueContainer() -> any SingleValueEncodingContainer {
        defer { count += 1 }

        return _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                           codingPath: nestedCodingPath,
                                                           boolEncoding: boolEncoding,
                                                           dataEncoding: dataEncoding,
                                                           dateEncoding: dateEncoding,
                                                           nilEncoding: nilEncoding)
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        defer { count += 1 }
        let container = _URLEncodedFormEncoder.KeyedContainer<NestedKey>(context: context,
                                                                         codingPath: nestedCodingPath,
                                                                         boolEncoding: boolEncoding,
                                                                         dataEncoding: dataEncoding,
                                                                         dateEncoding: dateEncoding,
                                                                         nilEncoding: nilEncoding)

        return KeyedEncodingContainer(container)
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        defer { count += 1 }

        return _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                       codingPath: nestedCodingPath,
                                                       boolEncoding: boolEncoding,
                                                       dataEncoding: dataEncoding,
                                                       dateEncoding: dateEncoding,
                                                       nilEncoding: nilEncoding)
    }

    func superEncoder() -> any Encoder {
        defer { count += 1 }

        return _URLEncodedFormEncoder(context: context,
                                      codingPath: codingPath,
                                      boolEncoding: boolEncoding,
                                      dataEncoding: dataEncoding,
                                      dateEncoding: dateEncoding,
                                      nilEncoding: nilEncoding)
    }
}

final class URLEncodedFormSerializer {
    private let alphabetizeKeyValuePairs: Bool
    private let arrayEncoding: URLEncodedFormEncoder.ArrayEncoding
    private let keyEncoding: URLEncodedFormEncoder.KeyEncoding
    private let keyPathEncoding: URLEncodedFormEncoder.KeyPathEncoding
    private let spaceEncoding: URLEncodedFormEncoder.SpaceEncoding
    private let allowedCharacters: CharacterSet

    init(alphabetizeKeyValuePairs: Bool,
         arrayEncoding: URLEncodedFormEncoder.ArrayEncoding,
         keyEncoding: URLEncodedFormEncoder.KeyEncoding,
         keyPathEncoding: URLEncodedFormEncoder.KeyPathEncoding,
         spaceEncoding: URLEncodedFormEncoder.SpaceEncoding,
         allowedCharacters: CharacterSet) {
        self.alphabetizeKeyValuePairs = alphabetizeKeyValuePairs
        self.arrayEncoding = arrayEncoding
        self.keyEncoding = keyEncoding
        self.keyPathEncoding = keyPathEncoding
        self.spaceEncoding = spaceEncoding
        self.allowedCharacters = allowedCharacters
    }

    func serialize(_ object: URLEncodedFormComponent.Object) -> String {
        var output: [String] = []
        for (key, component) in object {
            let value = serialize(component, forKey: key)
            output.append(value)
        }
        output = alphabetizeKeyValuePairs ? output.sorted() : output

        return output.joinedWithAmpersands()
    }

    func serialize(_ component: URLEncodedFormComponent, forKey key: String) -> String {
        switch component {
        case let .string(string): "\(escape(keyEncoding.encode(key)))=\(escape(string))"
        case let .array(array): serialize(array, forKey: key)
        case let .object(object): serialize(object, forKey: key)
        }
    }

    func serialize(_ object: URLEncodedFormComponent.Object, forKey key: String) -> String {
        var segments: [String] = object.map { subKey, value in
            let keyPath = keyPathEncoding.encodeKeyPath(subKey)
            return serialize(value, forKey: key + keyPath)
        }
        segments = alphabetizeKeyValuePairs ? segments.sorted() : segments

        return segments.joinedWithAmpersands()
    }

    func serialize(_ array: [URLEncodedFormComponent], forKey key: String) -> String {
        var segments: [String] = array.enumerated().map { index, component in
            let keyPath = arrayEncoding.encode(key, atIndex: index)
            return serialize(component, forKey: keyPath)
        }
        segments = alphabetizeKeyValuePairs ? segments.sorted() : segments

        return segments.joinedWithAmpersands()
    }

    func escape(_ query: String) -> String {
        var allowedCharactersWithSpace = allowedCharacters
        allowedCharactersWithSpace.insert(charactersIn: " ")
        let escapedQuery = query.addingPercentEncoding(withAllowedCharacters: allowedCharactersWithSpace) ?? query
        let spaceEncodedQuery = spaceEncoding.encode(escapedQuery)

        return spaceEncodedQuery
    }
}

extension [String] {
    func joinedWithAmpersands() -> String {
        joined(separator: "&")
    }
}

extension CharacterSet {
    public static let afURLQueryAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@"
        let subDelimitersToEncode = "!$&'()*+,;="
        let encodableDelimiters = CharacterSet(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

        return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
    }()
}
