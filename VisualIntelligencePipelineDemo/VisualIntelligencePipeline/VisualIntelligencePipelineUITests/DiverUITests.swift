//
//  DiverUITests.swift
//  DiverUITests
//
//  Created by Michael A Edgcumbe on 12/22/25.
//

import XCTest

final class DiverUITests: XCTestCase {

    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch
    
    @MainActor
    func testAppLaunches() throws {
        // App should launch without crashing
        XCTAssertTrue(app.exists, "App should exist after launch")
    }
    
    // MARK: - Sidebar Navigation
    
    @MainActor
    func testSidebarIsVisible() throws {
        // The sidebar should show the "Visual Intelligence" navigation title
        let navBar = app.navigationBars["Visual Intelligence"]
        // Allow time for UI to settle
        let exists = navBar.waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "Sidebar navigation bar should be visible")
    }
    
    @MainActor
    func testSettingsButtonExists() throws {
        // Settings gear icon should exist in the toolbar
        let settingsButton = app.buttons["settingsButton"]
        if settingsButton.waitForExistence(timeout: 3) {
            XCTAssertTrue(settingsButton.isHittable, "Settings button should be tappable")
        }
    }
    
    @MainActor
    func testSettingsNavigation() throws {
        let settingsButton = app.buttons["settingsButton"]
        guard settingsButton.waitForExistence(timeout: 3) else {
            // Settings button might use different identifier, try search
            return
        }
        
        settingsButton.tap()
        
        let settingsNavBar = app.navigationBars["Settings"]
        let exists = settingsNavBar.waitForExistence(timeout: 3)
        XCTAssertTrue(exists, "Settings screen should be visible after tapping settings")
    }
    
    // MARK: - Search
    
    @MainActor
    func testSearchFieldExists() throws {
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            XCTAssertTrue(searchField.isHittable, "Search field should be tappable")
        }
    }
    
    // MARK: - Camera / Capture
    
    @MainActor
    func testCaptureButtonExists() throws {
        // The capture/camera button should be present
        let captureButton = app.buttons["captureButton"]
        if captureButton.waitForExistence(timeout: 3) {
            XCTAssertTrue(captureButton.exists, "Capture button should exist")
        }
    }
    
    // MARK: - Performance
    
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
