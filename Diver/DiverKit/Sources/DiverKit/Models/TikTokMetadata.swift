//
//  TikTokMetadata.swift
//  Diver
//
//  Standardized TikTok metadata models matching backend schema
//

import Foundation

/// Content type for TikTok media
enum TikTokContentType: String, Codable {
    case video = "video"
    case images = "images"
    case unknown = "unknown"
}

/// TikTok author information
struct StandardTikTokAuthor: Codable {
    var id: String?
    var username: String?
    var nickname: String?
    var avatar: String?
    var verified: Bool?
    var followerCount: Int?
    var followingCount: Int?
    var videoCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, username, nickname, avatar, verified
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case videoCount = "video_count"
    }
    
    init() {
        self.id = nil
        self.username = nil
        self.nickname = nil
        self.avatar = nil
        self.verified = nil
        self.followerCount = nil
        self.followingCount = nil
        self.videoCount = nil
    }
}

/// TikTok engagement statistics
struct StandardTikTokStats: Codable {
    var viewCount: Int?
    var likeCount: Int?
    var commentCount: Int?
    var shareCount: Int?
    var playCount: Int?
    var downloadCount: Int?
    var collectCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case playCount = "play_count"
        case downloadCount = "download_count"
        case collectCount = "collect_count"
    }
    
    init() {
        self.viewCount = nil
        self.likeCount = nil
        self.commentCount = nil
        self.shareCount = nil
        self.playCount = nil
        self.downloadCount = nil
        self.collectCount = nil
    }
}

/// TikTok thumbnail information
struct StandardTikTokThumbnail: Codable {
    var url: String?
    var width: Int?
    var height: Int?
    
    init() {
        self.url = nil
        self.width = nil
        self.height = nil
    }
}

/// TikTok video format information
struct StandardTikTokFormat: Codable {
    var formatId: String?
    var url: String?
    var ext: String?
    var quality: String?
    var width: Int?
    var height: Int?
    var filesize: Int?
    var fps: Double?
    var vcodec: String?
    var acodec: String?
    var tbr: Double?
    var `protocol`: String?
    
    enum CodingKeys: String, CodingKey {
        case formatId = "format_id"
        case url, ext, quality, width, height, filesize, fps, vcodec, acodec, tbr
        case `protocol` = "protocol"
    }
    
    init() {
        self.formatId = nil
        self.url = nil
        self.ext = nil
        self.quality = nil
        self.width = nil
        self.height = nil
        self.filesize = nil
        self.fps = nil
        self.vcodec = nil
        self.acodec = nil
        self.tbr = nil
        self.`protocol` = nil
    }
}

/// TikTok music information
struct StandardTikTokMusic: Codable {
    var id: String?
    var title: String?
    var author: String?
    var album: String?
    var url: String?
    var duration: Double?
    var coverUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, album, url, duration
        case coverUrl = "cover_url"
    }
    
    init() {
        self.id = nil
        self.title = nil
        self.author = nil
        self.album = nil
        self.url = nil
        self.duration = nil
        self.coverUrl = nil
    }
}

/// Standardized TikTok metadata schema - consistent across all API versions
struct StandardTikTokMetadata: Codable, Identifiable {
    // Core identification
    var id: String
    var title: String
    var description: String
    var webpageUrl: String
    
    // Content classification
    var contentType: TikTokContentType
    
    // Author information
    var author: StandardTikTokAuthor
    
    // Timestamps
    var uploadDate: String?
    var createTime: Int?
    
    // Media properties
    var duration: Double
    
    // Engagement metrics
    var stats: StandardTikTokStats
    
    // Media content
    var thumbnail: String?
    var thumbnails: [StandardTikTokThumbnail]
    
    // Video-specific
    var formats: [StandardTikTokFormat]
    
    // Image carousel-specific
    var imageUrls: [String]
    
    // Music information
    var music: StandardTikTokMusic?
    
    // Metadata
    var tags: [String]
    var hashtags: [String]
    
    enum CodingKeys: String, CodingKey {
        case id, title, description
        case webpageUrl = "webpage_url"
        case contentType = "content_type"
        case author
        case uploadDate = "upload_date"
        case createTime = "create_time"
        case duration, stats, thumbnail, thumbnails, formats
        case imageUrls = "image_urls"
        case music, tags, hashtags
    }
    
    init() {
        self.id = ""
        self.title = ""
        self.description = ""
        self.webpageUrl = ""
        self.contentType = .unknown
        self.author = StandardTikTokAuthor()
        self.uploadDate = nil
        self.createTime = nil
        self.duration = 0.0
        self.stats = StandardTikTokStats()
        self.thumbnail = nil
        self.thumbnails = []
        self.formats = []
        self.imageUrls = []
        self.music = nil
        self.tags = []
        self.hashtags = []
    }
}
