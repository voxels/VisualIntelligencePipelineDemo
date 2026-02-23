import XCTest
import SwiftData
import Vision
@testable import DiverKit

@MainActor
final class PersonVectorTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUp() async throws {
        let schema = Schema([PersonVector.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }
    
    func testPersonVectorInitializationAndSave() throws {
        // Given: We create a dummy NSData object representing an archived vector.
        // We use an empty array just to stand in for the observation data during initialization validation.
        let dummyData = try NSKeyedArchiver.archivedData(withRootObject: NSArray(), requiringSecureCoding: true)
        let vector = PersonVector(
            name: "John Doe",
            localIdentifier: "test-person-1",
            featurePrintData: dummyData
        )
        
        // When: We insert and save the model
        modelContext.insert(vector)
        try modelContext.save()
        
        // Then: The vector is saved correctly
        let fetchDescriptor = FetchDescriptor<PersonVector>()
        let results = try modelContext.fetch(fetchDescriptor)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.localIdentifier, "test-person-1")
        XCTAssertEqual(results.first?.name, "John Doe")
        XCTAssertEqual(results.first?.featurePrintData, dummyData)
    }
    
    func testSerializationFailsGracefullyWithGarbageData() throws {
        let garbageData = "garbage".data(using: .utf8)!
        let vector = PersonVector(
            localIdentifier: "test-person-2",
            featurePrintData: garbageData
        )
        modelContext.insert(vector)
        try modelContext.save()
        
        // When we attempt to unarchive the observation from garbage it should throw
        XCTAssertThrowsError(try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: vector.featurePrintData!)) { error in
            XCTAssertNotNil(error)
        }
    }
    
}
