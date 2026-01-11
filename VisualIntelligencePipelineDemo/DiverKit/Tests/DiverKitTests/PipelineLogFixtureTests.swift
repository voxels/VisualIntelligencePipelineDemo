import XCTest
@testable import DiverKit

final class PipelineLogFixtureTests: XCTestCase {

    func testLoadDefaultFixture() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()

        XCTAssertFalse(fixture.logs.isEmpty, "Fixture should contain logs")
        XCTAssertGreaterThan(fixture.logs.count, 0, "Should have at least one log entry")
    }

    func testExtractReferences() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()
        let references = PipelineLogFixtureLoader.extractReferences(from: fixture)

        XCTAssertFalse(references.isEmpty, "Should extract at least one reference entity")

        // Verify reference structure
        if let firstRef = references.first {
            XCTAssertFalse(firstRef.entityType.isEmpty, "Entity type should not be empty")
            XCTAssertFalse(firstRef.name.isEmpty, "Name should not be empty")
            XCTAssertFalse(firstRef.id.isEmpty, "ID should not be empty")
        }
    }

    func testExtractCandidates() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()
        let candidates = PipelineLogFixtureLoader.extractCandidates(from: fixture)

        XCTAssertFalse(candidates.isEmpty, "Should extract at least one candidate")

        // Verify candidate structure
        if let firstCandidate = candidates.first {
            XCTAssertNotNil(firstCandidate.title, "Candidate should have a title")
            XCTAssertNotNil(firstCandidate.entityType, "Candidate should have entity type")
        }
    }

    func testReferenceMetadataStructure() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()
        let references = PipelineLogFixtureLoader.extractReferences(from: fixture)

        // Find a music reference
        let musicRef = references.first { $0.entityType == "music_album" }
        XCTAssertNotNil(musicRef, "Should have at least one music album reference")

        if let music = musicRef {
            let metadata = music.referenceMetadata
            XCTAssertNotNil(metadata.title, "Music metadata should have title")
            XCTAssertNotNil(metadata.artists, "Music metadata should have artists")
            XCTAssertNotNil(metadata.spotifyId, "Music metadata should have Spotify ID")
            XCTAssertNotNil(metadata.externalUrls, "Music metadata should have external URLs")
        }
    }

    func testFixtureLogStructure() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()

        for log in fixture.logs {
            XCTAssertFalse(log.jobUuid.isEmpty, "Job UUID should not be empty")
            XCTAssertFalse(log.inputId.isEmpty, "Input ID should not be empty")
            XCTAssertFalse(log.entries.isEmpty, "Log should have entries")

            for entry in log.entries {
                XCTAssertFalse(entry.context.isEmpty, "Entry context should not be empty")
            }
        }
    }

    func testMultipleReferenceTypes() throws {
        let fixture = try PipelineLogFixtureLoader.loadDefault()
        let references = PipelineLogFixtureLoader.extractReferences(from: fixture)

        let entityTypes = Set(references.map { $0.entityType })
        XCTAssertFalse(entityTypes.isEmpty, "Should have at least one entity type")

        // Log the types for debugging
        print("Found entity types: \(entityTypes)")
    }
}
