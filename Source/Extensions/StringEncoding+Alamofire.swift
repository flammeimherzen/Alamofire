
import Foundation

extension String.Encoding {
    init?(ianaCharsetName name: String) {
        switch name.lowercased() {
        case "utf-8":
            self = .utf8
        case "iso-8859-1":
            self = .isoLatin1
        case "unicode-1-1", "iso-10646-ucs-2", "utf-16":
            self = .utf16
        case "utf-16be":
            self = .utf16BigEndian
        case "utf-16le":
            self = .utf16LittleEndian
        case "utf-32":
            self = .utf32
        case "utf-32be":
            self = .utf32BigEndian
        case "utf-32le":
            self = .utf32LittleEndian
        default:
            return nil
        }
    }
}
