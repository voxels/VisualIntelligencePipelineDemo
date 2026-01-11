import Foundation
import Testing
import knowmaps
import DiverShared
@testable import Diver

@MainActor
struct KnowMapsAdapterTests {
    @Test func itemUsesURLHashIdentifier() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(url: url, title: "Example Place")

        #expect(item.id == Item.urlHash(for: url))
    }

    @Test func itemTitleFallsBackToHostWhenEmpty() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(url: url, title: "")

        #expect(item.title == "example.com")
    }

    @Test func metadataMappingUsesAllFields() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(
            url: url,
            title: "Example Place",
            descriptionText: "A brief description.",
            styleTags: ["coastal", "modern"],
            categories: ["coffee", "breakfast"],
            location: "Portland, OR",
            price: 12.5
        )

        let metadata = KnowMapsAdapter.metadata(from: item)

        #expect(metadata.id == item.id)
        #expect(metadata.title == "Example Place")
        #expect(metadata.descriptionText == "A brief description.")
        #expect(metadata.styleTags == ["coastal", "modern"])
        #expect(metadata.categories == ["coffee", "breakfast"])
        #expect(metadata.location == "Portland, OR")
        #expect(metadata.price == 12.5)
    }

    @Test func cachedRecordUsesStableIdentifiers() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(url: url, title: "Example Place")
        let record = KnowMapsAdapter.cachedRecord(from: item)
        let payload = try payloadDictionary(for: record)

        #expect(payload["recordId"] as? String == item.id)
        #expect(payload["identity"] as? String == item.id)
        #expect(payload["group"] as? String == KnowMapsAdapter.cacheGroup)
        #expect(payload["title"] as? String == item.title)
        #expect(payload["section"] as? String == KnowMapsAdapter.defaultSection)
        #expect(payload["rating"] as? Double == 1)
    }

    @Test func cachedRecordPrefersProvidedListLabel() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(
            url: url,
            title: "Example Place",
            descriptionText: nil,
            styleTags: ["modern"],
            categories: ["coffee"]
        )
        let record = KnowMapsAdapter.cachedRecord(from: item, list: "Custom")
        let payload = try payloadDictionary(for: record)

        #expect(payload["list"] as? String == "Custom")
    }

    @Test func cachedRecordUsesCategoryBeforeStyleTag() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let item = Item(
            url: url,
            title: "Example Place",
            descriptionText: nil,
            styleTags: ["modern"],
            categories: ["coffee"]
        )
        let record = KnowMapsAdapter.cachedRecord(from: item)
        let payload = try payloadDictionary(for: record)

        #expect(payload["list"] as? String == "coffee")
    }

    @Test func cachedRecordFallsBackToStyleTagThenDefault() async throws {
        let url = try #require(URL(string: "https://example.com/places/123"))
        let taggedItem = Item(
            url: url,
            title: "Example Place",
            descriptionText: nil,
            styleTags: ["modern"],
            categories: []
        )
        let taggedRecord = KnowMapsAdapter.cachedRecord(from: taggedItem)
        let taggedPayload = try payloadDictionary(for: taggedRecord)
        #expect(taggedPayload["list"] as? String == "modern")

        let fallbackItem = Item(url: url, title: "Example Place")
        let fallbackRecord = KnowMapsAdapter.cachedRecord(from: fallbackItem)
        let fallbackPayload = try payloadDictionary(for: fallbackRecord)
        #expect(fallbackPayload["list"] as? String == DiverListLabel.default)
    }

    private enum PayloadError: Error {
        case invalidPayload
    }

    private func payloadDictionary(for record: UserCachedRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw PayloadError.invalidPayload
        }
        return payload
    }
}
