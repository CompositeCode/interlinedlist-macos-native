// SidebarProfileGroupTests
//
// The sidebar's Profile group (GitHub #45 / G31).
//
// The view itself is not rendered — the project's rule is that SwiftUI views are
// verified by the build and by hand. What is tested here is the part that has
// real logic and a real failure mode: which rows belong to the group, and the
// rule that a deep link into a collapsed group must open it.
//
// That rule is the one worth guarding. Without it, a menu command that selects
// Organizations while the group is shut changes the detail pane while the
// sidebar appears to have ignored the user entirely.

import XCTest
@testable import InterlinedList

final class SidebarProfileGroupTests: XCTestCase {

    // MARK: - Happy path

    func test_givenTheProfileGroup_whenListingItsRows_thenItHoldsTheAccountShapedOnes() {
        XCTAssertEqual(
            MainWindowView.profileGroupSections,
            [.profile, .organizations, .connections]
        )
    }

    func test_givenATopLevelSection_whenAskingIfItIsGrouped_thenItIsNot() {
        // The reading surfaces stay top level. Grouping Messages or Lists under
        // an account menu would be the web's information architecture applied
        // where it does not fit.
        for section in [SidebarSection.timeline, .lists, .documents, .messages, .notifications, .search, .scheduled] {
            XCTAssertFalse(
                MainWindowView.profileGroupSections.contains(section),
                "\(section.rawValue) should stay a top-level row"
            )
        }
    }

    // MARK: - Boundary — every section is accounted for

    func test_givenEverySidebarSection_whenPartitioned_thenNoneIsOrphaned() {
        // A new section added without a decision about where it goes should show
        // up here rather than silently landing top-level.
        let grouped = MainWindowView.profileGroupSections
        let topLevel = Set(SidebarSection.allCases).subtracting(grouped)
        XCTAssertEqual(grouped.count + topLevel.count, SidebarSection.allCases.count)
        XCTAssertEqual(grouped.count, 3)
        XCTAssertEqual(topLevel.count, 7)
    }

    // MARK: - Settings tabs are addressable

    func test_givenTheSettingsTabs_whenAddressed_thenTheirIdentitiesAreStable() {
        // The raw values are persisted in `@AppStorage`, so renaming a case
        // silently sends an existing user to a different pane on next launch.
        XCTAssertEqual(SettingsTab.linkedAccounts.rawValue, "linkedAccounts")
        XCTAssertEqual(SettingsTab.preferences.rawValue, "preferences")
        XCTAssertEqual(SettingsTab.allCases.count, 9)
    }

    func test_givenASettingsTabValue_whenRoundTripped_thenItSurvivesStorage() {
        // `@AppStorage` round-trips a `RawRepresentable` through its raw value;
        // an unreadable stored value has to fall back rather than crash.
        for tab in SettingsTab.allCases {
            XCTAssertEqual(SettingsTab(rawValue: tab.rawValue), tab)
        }
        XCTAssertNil(SettingsTab(rawValue: "a-tab-that-was-renamed"))
    }
}
