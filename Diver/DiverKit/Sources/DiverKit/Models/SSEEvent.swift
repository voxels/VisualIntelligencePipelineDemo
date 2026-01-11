//
//  SSEEvent.swift
//  Diver
//
//  SSE event models for streaming data from backend
//

import Foundation

/// Base event data shared by all SSE event types
struct BaseEventData: Codable {
    let level: String
    let message: String
    let timestamp: String
    let jobUuid: String
    
    enum CodingKeys: String, CodingKey {
        case level, message, timestamp
        case jobUuid = "job_uuid"
    }
}

/// Log event data
struct LogEventData: Codable {
    let base: BaseEventData
    
    init(from decoder: Decoder) throws {
        self.base = try BaseEventData(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
    }
}

/// Item event data - Item is sent directly in data field
struct ItemEventData: Codable {
    let item: Item
    
    init(from decoder: Decoder) throws {
        // The entire data object IS the item
        self.item = try Item(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try item.encode(to: encoder)
    }
}

/// TikTok metadata event data - TikTok metadata is sent directly in data field
struct TikTokMetadataEventData: Codable {
    let metadata: StandardTikTokMetadata
    
    init(from decoder: Decoder) throws {
        // The entire data object IS the TikTok metadata
        self.metadata = try StandardTikTokMetadata(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try metadata.encode(to: encoder)
    }
}

/// Chat message event data - Message is sent directly in data field
struct ChatMessageEventData: Codable {
    let message: Message
    
    init(from decoder: Decoder) throws {
        // The entire data object IS the chat message
        self.message = try Message(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try message.encode(to: encoder)
    }
}

struct MediaAnalysisEventData: Codable {
    let mediaData: MediaRead
    
    init(from decoder: Decoder) throws {
        mediaData = try MediaRead(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try mediaData.encode(to: encoder)
    }
}

/// SSE Event with type discrimination
enum SSEEvent: Codable, Identifiable {
    case log(LogEventData)
    case item(ItemEventData)
    case tiktokMetadata(TikTokMetadataEventData)
    case chatMessage(ChatMessageEventData)
    case mediaAnalysis(MediaAnalysisEventData)
    
    var id: String {
        switch self {
        case .log:
            return UUID().uuidString
        case .item(let data):
            return data.item.id
        case .tiktokMetadata(let data):
            return data.metadata.id
        case .chatMessage(let data):
            return data.message.id
        case .mediaAnalysis(let data):
            return data.mediaData.id
        }
    }
    
    var jobUuid: String {
        switch self {
        case .log(let data): return data.base.jobUuid
        case .item(_): return ""  // ItemRead doesn't have input_id
        case .tiktokMetadata(let data): return data.metadata.id
        case .chatMessage(let data): return data.message.jobUuid
        case .mediaAnalysis(let data): return data.mediaData.itemId
        }
    }
    
    var timestamp: String {
        switch self {
        case .log(let data): return data.base.timestamp
        case .item(let data): return data.item.createdAt.ISO8601Format()
        case .tiktokMetadata(let data): return data.metadata.uploadDate ?? ""
        case .chatMessage(let data): return data.message.createdAt.ISO8601Format()
        case .mediaAnalysis(let data): return data.mediaData.createdAt.ISO8601Format()
        }
    }
    
    var message: String {
        switch self {
        case .log(let data): return data.base.message
        case .item(let data):
            return "Item: \(data.item.id)"
        case .tiktokMetadata(let data):
            if !data.metadata.title.isEmpty {
                return "TikTok: \(data.metadata.title)"
            } else if !data.metadata.description.isEmpty {
                return "TikTok: \(data.metadata.description.prefix(100))..."
            } else {
                return "TikTok metadata received"
            }
        case .chatMessage(let data):
            return "Chat: \(data.message.messageType)"
        case .mediaAnalysis(let data):
            return "Media analysis \(data.mediaData.id)"
        }
    }
    
    var level: String {
        switch self {
        case .log(let data): return data.base.level
        case .item: return "info"
        case .tiktokMetadata: return "info"
        case .chatMessage: return "info"
        case .mediaAnalysis: return "info"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type.lowercased() {
        case "log":
            let data = try container.decode(LogEventData.self, forKey: .data)
            self = .log(data)
        case "item":
            let data = try container.decode(ItemEventData.self, forKey: .data)
            self = .item(data)
        case "tiktokmetadata", "tiktok_metadata":
            let data = try container.decode(TikTokMetadataEventData.self, forKey: .data)
            self = .tiktokMetadata(data)
        case "chat_message", "chatmessage":
            let data = try container.decode(ChatMessageEventData.self, forKey: .data)
            self = .chatMessage(data)
        case "media_analysis", "mediaAnalysis", "media":
            let data = try container.decode(MediaAnalysisEventData.self, forKey: .data)
            self = .mediaAnalysis(data)
        default:
            let data = try container.decode(LogEventData.self, forKey: .data)
            self = .log(data)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .log(let data):
            try container.encode("log", forKey: .type)
            try container.encode(data, forKey: .data)
        case .item(let data):
            try container.encode("item", forKey: .type)
            try container.encode(data, forKey: .data)
        case .tiktokMetadata(let data):
            try container.encode("tiktokmetadata", forKey: .type)
            try container.encode(data, forKey: .data)
        case .chatMessage(let data):
            try container.encode("chat_message", forKey: .type)
            try container.encode(data, forKey: .data)
        case .mediaAnalysis(let data):
            try container.encode("media_analysis", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
    
    /// Display color based on log level
    var levelColor: String {
        switch level.lowercased() {
        case "info": return "blue"
        case "warning": return "orange"
        case "error": return "red"
        case "debug": return "gray"
        default: return "primary"
        }
    }
    
    /// Display icon based on message content
    var icon: String {
        // TikTok-specific icon
        if case .tiktokMetadata = self {
            return "video.fill"
        }
        
        if message.contains("📦") { return "shippingbox.fill" }
        if message.contains("🔍") { return "magnifyingglass" }
        if message.contains("📥") { return "arrow.down.circle.fill" }
        if message.contains("✅") { return "checkmark.circle.fill" }
        if message.contains("🎵") { return "music.note" }
        if message.contains("🤖") { return "cpu" }
        if message.contains("📊") { return "chart.bar.fill" }
        if message.contains("🔎") { return "magnifyingglass.circle" }
        if message.contains("💾") { return "externaldrive.fill" }
        if message.contains("✨") { return "sparkles" }
        return "circle.fill"
    }
}

// MARK: - Helper for AnyCodable

/// Type-erased Codable wrapper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - String to Date Helper

extension String {
    func toDate() -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: self)
    }
}
