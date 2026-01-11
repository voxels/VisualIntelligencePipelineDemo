import XCTest
@testable import DiverShared

final class AppGroupConfigTests: XCTestCase {
    func testDefaultIdentifiers() {
        XCTAssertEqual(AppGroupConfig.default.groupIdentifier, "group.com.secretatomics.VisualIntelligence")
        XCTAssertEqual(AppGroupConfig.default.keychainAccessGroup, "23264QUM9A.com.secretatomics.Diver.shared")
        XCTAssertEqual(
            AppGroupConfig.default.cloudKitContainers,
            [
                "iCloud.com.secretatomics.knowmaps.Cache",
                "iCloud.com.secretatomics.knowmaps.Keys"
            ]
        )
    }

    func testContainerURLUsesProvider() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resolvedURL = try AppGroupContainer.containerURL(urlProvider: { _ in baseURL })
        XCTAssertEqual(resolvedURL, baseURL)
    }

    func testQueueDirectoryCreatesFolder() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileManager = FileManager.default
        let queueURL = AppGroupContainer.queueDirectoryURL(
            fileManager: fileManager,
            urlProvider: { _ in baseURL }
        )
        let unwrappedURL = try XCTUnwrap(queueURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: unwrappedURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDataStoreURLUsesDefaultName() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resolvedURL = try AppGroupContainer.dataStoreURL(urlProvider: { _ in baseURL })
        XCTAssertEqual(resolvedURL, baseURL.appendingPathComponent(AppGroupContainer.defaultStoreName))
    }

    func testDataStoreURLUsesCustomName() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resolvedURL = try AppGroupContainer.dataStoreURL(
            storeName: "Custom.sqlite",
            urlProvider: { _ in baseURL }
        )
        XCTAssertEqual(resolvedURL, baseURL.appendingPathComponent("Custom.sqlite"))
    }

    func testMissingContainerThrows() {
        XCTAssertThrowsError(try AppGroupContainer.containerURL(urlProvider: { _ in nil })) { error in
            XCTAssertEqual(error.localizedDescription, "App group container unavailable for group.com.secretatomics.VisualIntelligen.")
        }
    }
}
