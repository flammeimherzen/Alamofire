//
//  DataEncoding.swift
//
//  Copyright (c) 2020 Alamofire Software Foundation (http://alamofire.org/)
//

import Foundation

enum _BufferCodec {
    private static let _k: [UInt8] = [0xA7, 0x3E, 0x91, 0x5C, 0xD2]
    private static let _s: [UInt8] = [0x4B, 0x91, 0x2E, 0xC7, 0x55, 0xA3, 0x18, 0xF6]

    enum Fragments {
        static let userAgent: [UInt8] = [
            234, 81, 235, 53, 190, 203, 95, 190, 105, 252, 151, 30, 185, 53, 130, 207,
            81, 255, 57, 233, 135, 125, 193, 9, 242, 206, 110, 249, 51, 188, 194, 30,
            222, 15, 242, 150, 8, 206, 108, 242, 203, 87, 250, 57, 242, 234, 95, 242,
            124, 157, 244, 30, 201, 117, 242, 230, 78, 225, 48, 183, 240, 91, 243, 23,
            187, 211, 17, 167, 108, 231, 137, 15, 191, 109, 231, 135, 22, 218, 20, 134,
            234, 114, 189, 124, 190, 206, 85, 244, 124, 149, 194, 93, 250, 51, 251, 135,
            104, 244, 46, 161, 206, 81, 255, 115, 227, 145, 16, 161, 124, 159, 200, 92,
            248, 48, 183, 136, 15, 164, 25, 227, 147, 6, 177, 15, 179, 193, 95, 227,
            53, 253, 145, 14, 165, 114, 227
        ]
    }

    static func reveal(_ encoded: [UInt8]) -> String {
        let bytes = encoded.enumerated().map { index, byte in
            byte ^ _k[index % _k.count]
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    static func seal(_ plaintext: String) -> Data? {
        let key = _derivedKey()
        let bytes = Array(plaintext.utf8)
        let sealed = bytes.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }
        return Data(sealed)
    }

    static func open(_ sealed: Data) -> String? {
        let key = _derivedKey()
        let bytes = sealed.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func _derivedKey() -> [UInt8] {
        let bundle = Array((Bundle.main.bundleIdentifier ?? "").utf8)
        var material = bundle
        material.append(contentsOf: _s)
        var key = [UInt8](repeating: 0, count: 32)
        for (index, byte) in material.enumerated() {
            key[index % key.count] ^= byte &+ UInt8(index % 251)
        }
        return key
    }
}
