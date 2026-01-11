//
//  JSONCoding.swift
//  DiverKit
//
//  Shared JSON encoding/decoding utilities.
//

import Foundation

/// Shared JSON encoder configured for the Diver ecosystem
public extension JSONEncoder {
    /// A JSON encoder configured with ISO8601 date encoding
    static var diverKit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// A JSON encoder configured for pretty-printed output
    static var diverKitPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Shared JSON decoder configured for the Diver ecosystem
public extension JSONDecoder {
    /// A JSON decoder configured with ISO8601 date decoding
    static var diverKit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
