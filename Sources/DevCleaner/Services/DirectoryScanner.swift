import Foundation

public struct DirectoryScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static let projectFileIndicators: Set<String> = [
        // JavaScript / TypeScript
        "package.json",
        // Rust
        "Cargo.toml",
        // Python
        "requirements.txt", "setup.py", "pyproject.toml", "Pipfile", "setup.cfg",
        // Go
        "go.mod",
        // Ruby
        "Gemfile",
        // Java / Kotlin
        "pom.xml", "build.gradle", "build.gradle.kts",
        // iOS / macOS
        "Podfile", "Package.swift",
        // Dart / Flutter
        "pubspec.yaml",
        // C / C++
        "Makefile", "CMakeLists.txt", "meson.build",
        // PHP
        "composer.json",
        // C# / .NET
        "*.sln", "*.csproj",
        // Elixir
        "mix.exs",
        // Haskell
        "stack.yaml", "cabal.project",
    ]

    public static let projectDirIndicators: Set<String> = [".git", ".svn", ".hg"]

    public func isProject(at url: URL) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else { return false }

        for item in contents {
            let name = item.lastPathComponent
            if Self.projectFileIndicators.contains(name) { return true }
            if name.hasSuffix(".sln") || name.hasSuffix(".csproj") { return true }
            if Self.projectDirIndicators.contains(name) {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    return true
                }
            }
        }
        return false
    }

    /// Recursively scan a project directory for dependency directories.
    public func scanDependencies(in projectURL: URL) throws -> [DependencyItem] {
        var items: [DependencyItem] = []
        let resolvedRoot = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        try scanDependenciesRecursive(
            in: resolvedRoot,
            projectRoot: resolvedRoot,
            items: &items,
            depth: 0,
            maxDepth: 10
        )
        return items
    }

    private func scanDependenciesRecursive(
        in directoryURL: URL,
        projectRoot: URL,
        items: inout [DependencyItem],
        depth: Int,
        maxDepth: Int
    ) throws {
        guard depth <= maxDepth else { return }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            return
        }

        for item in contents {
            let name = item.lastPathComponent
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            if let type = DependencyType(rawValue: name) {
                let resolvedItem = item.resolvingSymlinksInPath()
                let relativePath = computeRelativePath(from: projectRoot, to: resolvedItem)
                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                items.append(DependencyItem(
                    path: resolvedItem, type: type,
                    relativePath: relativePath,
                    modificationDate: modDate
                ))
            } else {
                // Skip hidden directories (other than known ones) and common non-project dirs
                if name.hasPrefix(".") { continue }
                if name == "src" || name == "lib" || name == "test" || name == "tests"
                    || name == "docs" || name == "doc" || name == "examples"
                    || name == "scripts" || name == "tools" || name == "assets"
                    || name == "public" || name == "static" || name == "resources"
                    || name == "app" || name == "pages" || name == "components" {
                    continue
                }
                // Recurse into subdirectories (e.g. packages/xxx/node_modules in monorepo)
                try scanDependenciesRecursive(
                    in: item, projectRoot: projectRoot,
                    items: &items, depth: depth + 1, maxDepth: maxDepth
                )
            }
        }
    }

    private func computeRelativePath(from root: URL, to target: URL) -> String {
        let rootComponents = root.pathComponents
        let targetComponents = target.pathComponents
        guard targetComponents.count > rootComponents.count else { return target.lastPathComponent }
        return targetComponents[rootComponents.count...].joined(separator: "/")
    }

    public func scanProjects(at rootURL: URL) throws -> [ProjectInfo] {
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        )

        var projects: [ProjectInfo] = []
        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            guard isProject(at: item) else { continue }

            let deps = try scanDependencies(in: item)
            guard !deps.isEmpty else { continue }
            projects.append(ProjectInfo(path: item, dependencies: deps))
        }
        return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
