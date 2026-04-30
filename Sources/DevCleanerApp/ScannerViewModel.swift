import Foundation
import SwiftUI
import DevCleanerLib

@MainActor
class ScannerViewModel: ObservableObject {
    @Published var rootPath: String = ""
    @Published var projects: [ProjectInfo] = []
    @Published var isScanning: Bool = false
    @Published var isCalculatingSize: Bool = false
    @Published var isRemoving: Bool = false
    @Published var statusMessage: String = ""
    @Published var showRemoveConfirmation: Bool = false
    @Published var lastError: String?

    @Published var projectSortField: SortField = .name
    @Published var projectSortOrder: SortDirection = .ascending
    @Published var depSortField: SortField = .size
    @Published var depSortOrder: SortDirection = .descending

    private let scanner = DirectoryScanner()
    private let sizeCalc = SizeCalculator()
    private let cleaner = DependencyCleaner()

    var totalSelectedSize: Int64 {
        projects.reduce(0) { $0 + $1.selectedSize }
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file)
    }

    var selectedItemCount: Int {
        projects.reduce(0) { total, project in
            total + project.dependencies.filter({ $0.isSelected }).count
        }
    }

    var totalDependencyCount: Int {
        projects.reduce(0) { $0 + $1.dependencies.count }
    }

    var totalSize: Int64 {
        projects.reduce(0) { $0 + $1.totalSize }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // MARK: - Sorting

    func applySorting() {
        sortProjects()
        for i in projects.indices {
            projects[i].dependencies = sortedDeps(projects[i].dependencies)
        }
    }

    private func sortProjects() {
        let ascending = projectSortOrder.isAscending
        switch projectSortField {
        case .name:
            projects.sort {
                let r = $0.name.localizedCaseInsensitiveCompare($1.name)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .size:
            projects.sort { ascending ? $0.totalSize < $1.totalSize : $0.totalSize > $1.totalSize }
        case .modDate:
            projects.sort {
                let d0 = $0.dependencies.compactMap(\.modificationDate).max() ?? .distantPast
                let d1 = $1.dependencies.compactMap(\.modificationDate).max() ?? .distantPast
                return ascending ? d0 < d1 : d0 > d1
            }
        }
    }

    private func sortedDeps(_ deps: [DependencyItem]) -> [DependencyItem] {
        let ascending = depSortOrder.isAscending
        switch depSortField {
        case .name:
            return deps.sorted {
                let r = $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .size:
            return deps.sorted { ascending ? $0.sizeInBytes < $1.sizeInBytes : $0.sizeInBytes > $1.sizeInBytes }
        case .modDate:
            return deps.sorted {
                let d0 = $0.modificationDate ?? .distantPast
                let d1 = $1.modificationDate ?? .distantPast
                return ascending ? d0 < d1 : d0 > d1
            }
        }
    }

    // MARK: - Actions

    func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择工作区根目录"
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            Task { await scan() }
        }
    }

    func scan() async {
        guard !rootPath.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        isScanning = true
        statusMessage = "正在扫描项目..."
        lastError = nil

        let scannerCopy = scanner
        do {
            let scannedProjects = try await Task.detached {
                try scannerCopy.scanProjects(at: rootURL)
            }.value
            projects = scannedProjects
            statusMessage = "发现 \(projects.count) 个项目，\(totalDependencyCount) 个依赖目录。正在计算大小..."
            isScanning = false
            await calculateSizes()
        } catch {
            lastError = "扫描失败: \(error.localizedDescription)"
            isScanning = false
        }
    }

    func calculateSizes() async {
        isCalculatingSize = true

        struct SizeTask: Sendable {
            let projectID: String
            let depID: String
            let url: URL
        }

        var tasks: [SizeTask] = []
        for project in projects {
            for dep in project.dependencies {
                tasks.append(SizeTask(projectID: project.id, depID: dep.id, url: dep.path))
            }
        }

        let sizeCalcCopy = sizeCalc
        let total = tasks.count
        for (idx, task) in tasks.enumerated() {
            let size: Int64
            do {
                size = try await Task.detached {
                    try sizeCalcCopy.directorySize(at: task.url)
                }.value
            } catch {
                size = -1
            }

            if let pi = projects.firstIndex(where: { $0.id == task.projectID }),
               let di = projects[pi].dependencies.firstIndex(where: { $0.id == task.depID }) {
                projects[pi].dependencies[di].sizeInBytes = size
            }

            if (idx + 1) % 5 == 0 || idx == total - 1 {
                statusMessage = "正在计算大小... (\(idx + 1)/\(total))"
            }
        }

        applySorting()
        isCalculatingSize = false
        statusMessage = "扫描完成 — 共 \(projects.count) 个项目，\(totalDependencyCount) 个依赖项，总计 \(formattedTotalSize)"
    }

    func toggleProject(_ projectID: String, selected: Bool) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        for j in projects[idx].dependencies.indices {
            projects[idx].dependencies[j].isSelected = selected
        }
    }

    func toggleDependency(projectID: String, depID: String) {
        guard let pi = projects.firstIndex(where: { $0.id == projectID }),
              let di = projects[pi].dependencies.firstIndex(where: { $0.id == depID })
        else { return }
        projects[pi].dependencies[di].isSelected.toggle()
    }

    func toggleExpand(_ projectID: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].isExpanded.toggle()
    }

    func selectAll() {
        for i in projects.indices {
            for j in projects[i].dependencies.indices {
                projects[i].dependencies[j].isSelected = true
            }
        }
    }

    func deselectAll() {
        for i in projects.indices {
            for j in projects[i].dependencies.indices {
                projects[i].dependencies[j].isSelected = false
            }
        }
    }

    func confirmRemove() {
        guard selectedItemCount > 0 else { return }
        showRemoveConfirmation = true
    }

    func removeSelected() async {
        isRemoving = true
        statusMessage = "正在删除..."
        let itemsToRemove = projects.flatMap { $0.dependencies.filter({ $0.isSelected }) }

        let cleanerCopy = cleaner
        do {
            let removed = try await Task.detached {
                try cleanerCopy.remove(items: itemsToRemove)
            }.value
            let removedPaths = Set(removed.map { $0.path })

            for i in projects.indices {
                projects[i].dependencies.removeAll { removedPaths.contains($0.path.path) }
            }
            projects.removeAll { $0.dependencies.isEmpty }

            statusMessage = "已删除 \(removed.count) 个依赖目录"
        } catch {
            lastError = "删除失败: \(error.localizedDescription)"
        }
        isRemoving = false
    }
}
