import Foundation
import Testing
@testable import Ghostty

@Suite struct ProjectHomeTests {
    @Test func missingDirectoryConfigurationHidesHome() throws {
        let config = try TemporaryConfig("")
        #expect(ProjectHome.configuration(from: config) == nil)
    }

    @Test func unavailableDirectoryHidesHome() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = try TemporaryConfig("macos-project-home-directory = \(missing.path)")
        #expect(ProjectHome.configuration(from: config) == nil)
    }

    @Test func scansOnlyMatchingSecondLevelDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let group = root.appendingPathComponent("Team One")
        let manager = FileManager.default
        try manager.createDirectory(at: group.appendingPathComponent("foo-api"), withIntermediateDirectories: true)
        try manager.createDirectory(at: group.appendingPathComponent("foo-admin"), withIntermediateDirectories: true)
        try manager.createDirectory(
            at: group.appendingPathComponent("foo-admin-api"),
            withIntermediateDirectories: true
        )
        try manager.createDirectory(at: group.appendingPathComponent("foo-other"), withIntermediateDirectories: true)
        try Data().write(to: group.appendingPathComponent("fake-api"))

        let ghosttyConfig = try TemporaryConfig("macos-project-home-directory = \(root.path)")
        let config = try #require(ProjectHome.configuration(from: ghosttyConfig))
        #expect(ProjectHome.groups(for: config).map(\.name) == ["Team One"])
        #expect(ProjectHome.groups(for: config).first?.projects.map(\.name) == [
            "foo-admin", "foo-admin-api", "foo-api"
        ])
    }

    @Test func customSuffixesReplaceDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let group = root.appendingPathComponent("Group")
        try FileManager.default.createDirectory(
            at: group.appendingPathComponent("service-api"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: group.appendingPathComponent("service-web"),
            withIntermediateDirectories: true
        )

        let ghosttyConfig = try TemporaryConfig("""
        macos-project-home-directory = \(root.path)
        macos-project-home-suffixes = -web
        """)
        let config = try #require(ProjectHome.configuration(from: ghosttyConfig))
        #expect(ProjectHome.groups(for: config).first?.projects.map(\.name) == ["service-web"])
    }
}
