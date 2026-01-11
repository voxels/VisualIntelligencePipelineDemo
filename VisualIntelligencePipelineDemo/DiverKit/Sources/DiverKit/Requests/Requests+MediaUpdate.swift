import Foundation

extension Requests {
    public struct MediaUpdate: Codable, Hashable, Sendable {
        public let title: String?
        public let description: String?
        public let altText: String?
        public let tags: [String]?
        public let extractedText: String?
        public let detectedObjects: [String]?
        public let colors: [String]?
        public let mood: String?
        public let transcription: String?
        public let colorPalette: [String: Double?]?
        public let colorDistribution: [String: JSONValue]?
        public let colorTemperature: String?
        public let colorHarmony: String?
        public let dominantHue: String?
        public let colorVibrancy: String?
        public let colorScheme: String?
        public let style: String?
        public let composition: String?
        public let lighting: String?
        public let setting: String?
        public let peopleCount: Int?
        public let facesDetected: [String]?
        public let themes: [String]?
        public let concepts: [String]?
        public let activities: [String]?
        public let brandsDetected: [String]?
        public let blurLevel: String?
        public let saturation: String?
        public let contrast: String?
        public let brightness: String?
        public let texture: [String]?
        public let qualityScore: Double?
        public let viewCount: Int?
        public let downloadCount: Int?
        public let analysisResult: [String: JSONValue]?
        public let thumbnails: [String]?
        public let visualDescription: String?
        /// Additional properties that are not explicitly defined in the schema
        public let additionalProperties: [String: JSONValue]

        public init(
            title: String? = nil,
            description: String? = nil,
            altText: String? = nil,
            tags: [String]? = nil,
            extractedText: String? = nil,
            detectedObjects: [String]? = nil,
            colors: [String]? = nil,
            mood: String? = nil,
            transcription: String? = nil,
            colorPalette: [String: Double?]? = nil,
            colorDistribution: [String: JSONValue]? = nil,
            colorTemperature: String? = nil,
            colorHarmony: String? = nil,
            dominantHue: String? = nil,
            colorVibrancy: String? = nil,
            colorScheme: String? = nil,
            style: String? = nil,
            composition: String? = nil,
            lighting: String? = nil,
            setting: String? = nil,
            peopleCount: Int? = nil,
            facesDetected: [String]? = nil,
            themes: [String]? = nil,
            concepts: [String]? = nil,
            activities: [String]? = nil,
            brandsDetected: [String]? = nil,
            blurLevel: String? = nil,
            saturation: String? = nil,
            contrast: String? = nil,
            brightness: String? = nil,
            texture: [String]? = nil,
            qualityScore: Double? = nil,
            viewCount: Int? = nil,
            downloadCount: Int? = nil,
            analysisResult: [String: JSONValue]? = nil,
            thumbnails: [String]? = nil,
            visualDescription: String? = nil,
            additionalProperties: [String: JSONValue] = .init()
        ) {
            self.title = title
            self.description = description
            self.altText = altText
            self.tags = tags
            self.extractedText = extractedText
            self.detectedObjects = detectedObjects
            self.colors = colors
            self.mood = mood
            self.transcription = transcription
            self.colorPalette = colorPalette
            self.colorDistribution = colorDistribution
            self.colorTemperature = colorTemperature
            self.colorHarmony = colorHarmony
            self.dominantHue = dominantHue
            self.colorVibrancy = colorVibrancy
            self.colorScheme = colorScheme
            self.style = style
            self.composition = composition
            self.lighting = lighting
            self.setting = setting
            self.peopleCount = peopleCount
            self.facesDetected = facesDetected
            self.themes = themes
            self.concepts = concepts
            self.activities = activities
            self.brandsDetected = brandsDetected
            self.blurLevel = blurLevel
            self.saturation = saturation
            self.contrast = contrast
            self.brightness = brightness
            self.texture = texture
            self.qualityScore = qualityScore
            self.viewCount = viewCount
            self.downloadCount = downloadCount
            self.analysisResult = analysisResult
            self.thumbnails = thumbnails
            self.visualDescription = visualDescription
            self.additionalProperties = additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.altText = try container.decodeIfPresent(String.self, forKey: .altText)
            self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
            self.extractedText = try container.decodeIfPresent(String.self, forKey: .extractedText)
            self.detectedObjects = try container.decodeIfPresent([String].self, forKey: .detectedObjects)
            self.colors = try container.decodeIfPresent([String].self, forKey: .colors)
            self.mood = try container.decodeIfPresent(String.self, forKey: .mood)
            self.transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
            self.colorPalette = try container.decodeIfPresent([String: Double?].self, forKey: .colorPalette)
            self.colorDistribution = try container.decodeIfPresent([String: JSONValue].self, forKey: .colorDistribution)
            self.colorTemperature = try container.decodeIfPresent(String.self, forKey: .colorTemperature)
            self.colorHarmony = try container.decodeIfPresent(String.self, forKey: .colorHarmony)
            self.dominantHue = try container.decodeIfPresent(String.self, forKey: .dominantHue)
            self.colorVibrancy = try container.decodeIfPresent(String.self, forKey: .colorVibrancy)
            self.colorScheme = try container.decodeIfPresent(String.self, forKey: .colorScheme)
            self.style = try container.decodeIfPresent(String.self, forKey: .style)
            self.composition = try container.decodeIfPresent(String.self, forKey: .composition)
            self.lighting = try container.decodeIfPresent(String.self, forKey: .lighting)
            self.setting = try container.decodeIfPresent(String.self, forKey: .setting)
            self.peopleCount = try container.decodeIfPresent(Int.self, forKey: .peopleCount)
            self.facesDetected = try container.decodeIfPresent([String].self, forKey: .facesDetected)
            self.themes = try container.decodeIfPresent([String].self, forKey: .themes)
            self.concepts = try container.decodeIfPresent([String].self, forKey: .concepts)
            self.activities = try container.decodeIfPresent([String].self, forKey: .activities)
            self.brandsDetected = try container.decodeIfPresent([String].self, forKey: .brandsDetected)
            self.blurLevel = try container.decodeIfPresent(String.self, forKey: .blurLevel)
            self.saturation = try container.decodeIfPresent(String.self, forKey: .saturation)
            self.contrast = try container.decodeIfPresent(String.self, forKey: .contrast)
            self.brightness = try container.decodeIfPresent(String.self, forKey: .brightness)
            self.texture = try container.decodeIfPresent([String].self, forKey: .texture)
            self.qualityScore = try container.decodeIfPresent(Double.self, forKey: .qualityScore)
            self.viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
            self.downloadCount = try container.decodeIfPresent(Int.self, forKey: .downloadCount)
            self.analysisResult = try container.decodeIfPresent([String: JSONValue].self, forKey: .analysisResult)
            self.thumbnails = try container.decodeIfPresent([String].self, forKey: .thumbnails)
            self.visualDescription = try container.decodeIfPresent(String.self, forKey: .visualDescription)
            self.additionalProperties = try decoder.decodeAdditionalProperties(using: CodingKeys.self)
        }

        public func encode(to encoder: Encoder) throws -> Void {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try encoder.encodeAdditionalProperties(self.additionalProperties)
            try container.encodeIfPresent(self.title, forKey: .title)
            try container.encodeIfPresent(self.description, forKey: .description)
            try container.encodeIfPresent(self.altText, forKey: .altText)
            try container.encodeIfPresent(self.tags, forKey: .tags)
            try container.encodeIfPresent(self.extractedText, forKey: .extractedText)
            try container.encodeIfPresent(self.detectedObjects, forKey: .detectedObjects)
            try container.encodeIfPresent(self.colors, forKey: .colors)
            try container.encodeIfPresent(self.mood, forKey: .mood)
            try container.encodeIfPresent(self.transcription, forKey: .transcription)
            try container.encodeIfPresent(self.colorPalette, forKey: .colorPalette)
            try container.encodeIfPresent(self.colorDistribution, forKey: .colorDistribution)
            try container.encodeIfPresent(self.colorTemperature, forKey: .colorTemperature)
            try container.encodeIfPresent(self.colorHarmony, forKey: .colorHarmony)
            try container.encodeIfPresent(self.dominantHue, forKey: .dominantHue)
            try container.encodeIfPresent(self.colorVibrancy, forKey: .colorVibrancy)
            try container.encodeIfPresent(self.colorScheme, forKey: .colorScheme)
            try container.encodeIfPresent(self.style, forKey: .style)
            try container.encodeIfPresent(self.composition, forKey: .composition)
            try container.encodeIfPresent(self.lighting, forKey: .lighting)
            try container.encodeIfPresent(self.setting, forKey: .setting)
            try container.encodeIfPresent(self.peopleCount, forKey: .peopleCount)
            try container.encodeIfPresent(self.facesDetected, forKey: .facesDetected)
            try container.encodeIfPresent(self.themes, forKey: .themes)
            try container.encodeIfPresent(self.concepts, forKey: .concepts)
            try container.encodeIfPresent(self.activities, forKey: .activities)
            try container.encodeIfPresent(self.brandsDetected, forKey: .brandsDetected)
            try container.encodeIfPresent(self.blurLevel, forKey: .blurLevel)
            try container.encodeIfPresent(self.saturation, forKey: .saturation)
            try container.encodeIfPresent(self.contrast, forKey: .contrast)
            try container.encodeIfPresent(self.brightness, forKey: .brightness)
            try container.encodeIfPresent(self.texture, forKey: .texture)
            try container.encodeIfPresent(self.qualityScore, forKey: .qualityScore)
            try container.encodeIfPresent(self.viewCount, forKey: .viewCount)
            try container.encodeIfPresent(self.downloadCount, forKey: .downloadCount)
            try container.encodeIfPresent(self.analysisResult, forKey: .analysisResult)
            try container.encodeIfPresent(self.thumbnails, forKey: .thumbnails)
            try container.encodeIfPresent(self.visualDescription, forKey: .visualDescription)
        }

        /// Keys for encoding/decoding struct properties.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case title
            case description
            case altText = "alt_text"
            case tags
            case extractedText = "extracted_text"
            case detectedObjects = "detected_objects"
            case colors
            case mood
            case transcription
            case colorPalette = "color_palette"
            case colorDistribution = "color_distribution"
            case colorTemperature = "color_temperature"
            case colorHarmony = "color_harmony"
            case dominantHue = "dominant_hue"
            case colorVibrancy = "color_vibrancy"
            case colorScheme = "color_scheme"
            case style
            case composition
            case lighting
            case setting
            case peopleCount = "people_count"
            case facesDetected = "faces_detected"
            case themes
            case concepts
            case activities
            case brandsDetected = "brands_detected"
            case blurLevel = "blur_level"
            case saturation
            case contrast
            case brightness
            case texture
            case qualityScore = "quality_score"
            case viewCount = "view_count"
            case downloadCount = "download_count"
            case analysisResult = "analysis_result"
            case thumbnails
            case visualDescription = "visual_description"
        }
    }
}