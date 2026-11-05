import AppKit
import SwiftUI

/// An optional project launcher configured through Ghostty's config.ghostty.
enum ProjectHome {
    struct Configuration {
        let rootDirectory: String
        let suffixes: [String]

        var directoryURL: URL {
            URL(fileURLWithPath: (rootDirectory as NSString).expandingTildeInPath)
        }

    }

    struct Group: Identifiable {
        let name: String
        let projects: [Project]
        var id: String { name }
    }

    struct Project: Identifiable {
        let name: String
        let url: URL
        var id: URL { url }
    }

    static func configuration() -> Configuration? {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return nil }
        return configuration(from: appDelegate.ghostty.config)
    }

    static func configuration(from config: Ghostty.Config) -> Configuration? {
        guard let rootDirectory = config.macosProjectHomeDirectory else { return nil }
        let path = (rootDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let suffixes = config.macosProjectHomeSuffixes.map { value in
            value.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } ?? ["-api", "-admin", "-admin-api"]
        return Configuration(rootDirectory: rootDirectory, suffixes: suffixes)
    }

    static func groups(for config: Configuration) -> [Group] {
        let manager = FileManager.default
        guard let directories = try? manager.contentsOfDirectory(
            at: config.directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return directories.filter(isDirectory).compactMap { groupURL in
            guard let children = try? manager.contentsOfDirectory(
                at: groupURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }

            let projects = children.filter { child in
                isDirectory(child) && config.suffixes.contains { child.lastPathComponent.hasSuffix($0) }
            }.map { Project(name: $0.lastPathComponent, url: $0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return Group(name: groupURL.lastPathComponent, projects: projects)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private final class ProjectHomeModel: ObservableObject {
    @Published var groups: [ProjectHome.Group] = []
    @Published var searchText = ""

    var filteredGroups: [ProjectHome.Group] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.name.localizedStandardContains(query) { return group }
            let projects = group.projects.filter { $0.name.localizedStandardContains(query) }
            return projects.isEmpty ? nil : .init(name: group.name, projects: projects)
        }
    }

    func reload() {
        guard let config = ProjectHome.configuration() else {
            groups = []
            return
        }
        groups = ProjectHome.groups(for: config)
    }
}

private struct ProjectHomeView: View {
    @ObservedObject var model: ProjectHomeModel
    let openProject: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projects")
                .font(.largeTitle.bold())
            TextField("Search projects", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search projects")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.filteredGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name)
                                .font(.headline)
                            ForEach(group.projects) { project in
                                Button {
                                    openProject(project.url)
                                } label: {
                                    Label(project.name, systemImage: "folder")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .help(project.url.path)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.filteredGroups.isEmpty {
                Text(model.searchText.isEmpty ? "No matching project directories" : "No search results")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }
}

final class ProjectHomeController: NSWindowController, NSWindowDelegate {
    private static var openControllers: [ProjectHomeController] = []
    private let model = ProjectHomeModel()
    private let homeAccessory = NSTitlebarAccessoryViewController()

    static func refreshAll() {
        let controllers = openControllers
        if ProjectHome.configuration() == nil {
            controllers.forEach { $0.window?.close() }
        } else {
            controllers.forEach { $0.model.reload() }
        }
    }

    static func show(from parent: TerminalWindow) {
        guard ProjectHome.configuration() != nil else { return }
        if let existing = parent.tabGroup?.windows.first(where: { $0.windowController is ProjectHomeController }),
           let controller = existing.windowController as? ProjectHomeController {
            controller.model.reload()
            parent.tabGroup?.selectedWindow = existing
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ProjectHomeController(parent: parent)
        openControllers.append(controller)
        guard let window = controller.window else { return }
        if parent.tabbingMode != .disallowed {
            _ = parent.addTabbedWindowSafely(window, ordered: .below)
            parent.tabGroup?.selectedWindow = window
        }
        _ = controller.showWindowSafely(nil)
    }

    private init(parent: TerminalWindow) {
        let window = NSWindow(
            contentRect: parent.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Projects"
        window.tabbingMode = .preferred
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        let homeButton = NSButton(
            image: NSImage(systemSymbolName: "house", accessibilityDescription: "Projects") ?? NSImage(),
            target: self,
            action: #selector(refreshHome(_:))
        )
        homeButton.isBordered = false
        homeButton.toolTip = "Projects"
        homeButton.frame = NSRect(x: 0, y: 0, width: 32, height: 28)
        homeAccessory.layoutAttribute = .left
        homeAccessory.view = homeButton
        window.addTitlebarAccessoryViewController(homeAccessory)
        window.contentView = NSHostingView(rootView: ProjectHomeView(model: model) { [weak self] url in
            self?.openProject(url)
        })
        model.reload()
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }

    @objc private func refreshHome(_ sender: Any?) {
        model.reload()
    }

    private func openProject(_ url: URL) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = url.path

        if let terminal = window?.tabGroup?.windows.compactMap({ $0 as? TerminalWindow }).first {
            _ = TerminalController.newTab(appDelegate.ghostty, from: terminal, withBaseConfig: config)
        } else {
            let controller = TerminalController.newWindow(appDelegate.ghostty, withBaseConfig: config)
            if let newWindow = controller.window, let window {
                _ = window.addTabbedWindowSafely(newWindow, ordered: .above)
                window.tabGroup?.selectedWindow = newWindow
            }
        }
    }
}
