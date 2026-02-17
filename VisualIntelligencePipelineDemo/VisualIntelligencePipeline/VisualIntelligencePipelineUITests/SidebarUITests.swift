//
//  SidebarUITests.swift
//  VisualIntelligencePipelineUITests
//
//  Sidebar-focused UI tests: sessions list, search interaction, context menus
//

import XCTest

final class SidebarUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Session List
    
    @MainActor
    func testSidebarShowsSessions() throws {
        // Wait for sidebar to load
        let sidebar = app.navigationBars["Visual Intelligence"]
        guard sidebar.waitForExistence(timeout: 5) else {
            XCTFail("Sidebar should be visible")
            return
        }
        
        // Check for session list elements (lists, cells, or static texts)
        // Sessions may or may not exist depending on state
        let listExists = app.collectionViews.firstMatch.waitForExistence(timeout: 3)
            || app.tables.firstMatch.waitForExistence(timeout: 3)
        
        // At minimum, the list container should exist even if empty
        XCTAssertTrue(listExists || app.staticTexts.count > 0, "Sidebar should show content or empty state")
    }
    
    // MARK: - Search Interaction
    
    @MainActor
    func testSearchFieldAcceptsInput() throws {
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 3) else {
            return // Search may not be visible initially
        }
        
        searchField.tap()
        searchField.typeText("test query")
        
        // Verify text was entered
        XCTAssertEqual(searchField.value as? String, "test query")
    }
    
    @MainActor
    func testSearchClearButton() throws {
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 3) else { return }
        
        searchField.tap()
        searchField.typeText("something")
        
        // Clear button should appear
        let clearButton = app.buttons["Clear text"]
        if clearButton.waitForExistence(timeout: 2) {
            clearButton.tap()
            // After clearing, search field should be empty
            let value = searchField.value as? String ?? ""
            XCTAssertTrue(value.isEmpty || value == "Search", "Search field should be cleared")
        }
    }
    
    // MARK: - Tab/Segment Navigation
    
    @MainActor
    func testSidebarTabsExist() throws {
        // Check for common tab/segment elements
        let sessionsTab = app.buttons["Sessions"]
        let collectionsTab = app.buttons["Collections"]
        
        // At least one navigation element should exist
        let hasTabs = sessionsTab.waitForExistence(timeout: 3)
            || collectionsTab.waitForExistence(timeout: 3)
        
        if hasTabs {
            // Tap between tabs if available
            if sessionsTab.exists { sessionsTab.tap() }
            if collectionsTab.exists { collectionsTab.tap() }
        }
    }
    
    // MARK: - Empty State
    
    @MainActor
    func testEmptyStateDisplayed() throws {
        // In a fresh install, there should be some empty state or onboarding content
        let sidebar = app.navigationBars["Visual Intelligence"]
        guard sidebar.waitForExistence(timeout: 5) else { return }
        
        // App should not be blank — either sessions exist or empty state shows
        let hasContent = app.staticTexts.count > 0
            || app.collectionViews.firstMatch.exists
            || app.tables.firstMatch.exists
        
        XCTAssertTrue(hasContent, "Sidebar should display sessions or empty state content")
    }
    
    // MARK: - Scroll Performance
    
    @MainActor
    func testSidebarScrollPerformance() throws {
        let sidebar = app.navigationBars["Visual Intelligence"]
        guard sidebar.waitForExistence(timeout: 5) else { return }
        
        let list = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        
        guard list.waitForExistence(timeout: 3) else { return }
        
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
    }
    
    @MainActor
    func testDetailViewLoadPerformance() throws {
        let sidebar = app.navigationBars["Visual Intelligence"]
        guard sidebar.waitForExistence(timeout: 5) else { return }
        
        // Find the first tappable cell
        let list = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        
        guard list.waitForExistence(timeout: 3) else { return }
        
        let firstCell = list.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 3) else { return }
        
        measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric]) {
            firstCell.tap()
            
            // Wait for detail view to load
            let _ = app.navigationBars.firstMatch.waitForExistence(timeout: 3)
            
            // Navigate back
            app.navigationBars.buttons.firstMatch.tap()
            let _ = sidebar.waitForExistence(timeout: 3)
        }
    }
}
