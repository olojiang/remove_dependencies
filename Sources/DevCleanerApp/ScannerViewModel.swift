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
    @Published var showCreateCollectionPrompt: Bool = false
    @Published var showCollections: Bool = false
    @Published var showCollectionDeleteConfirmation: Bool = false
    @Published var showCollectionItemsRemoveConfirmation: Bool = false
    @Published var showCollectionDirectoriesRemoveConfirmation: Bool = false
    @Published var lastError: String?
    @Published private var calculatedSizeDependencyIDs: Set<String> = []
    @Published var collections: [DirectoryCollection] = []
    @Published var selectedCollectionID: UUID?
    @Published var newCollectionName: String = ""

    @Published var projectSortField: SortField = .size
    @Published var projectSortOrder: SortDirection = .descending
    @Published var depSortField: SortField = .size
    @Published var depSortOrder: SortDirection = .descending

    private let scanner = DirectoryScanner()
    private let sizeCalc = SizeCalculator()
    private let sizeCache = DirectorySizeCache()
    private let cleaner = DependencyCleaner()
    private let collectionStore = DirectoryCollectionStore()
    private let rootPathDefaultsKey = "lastSelectedRootPath"
    private var hasPerformedInitialScan = false

    init() {
        rootPath = UserDefaults.standard.string(forKey: rootPathDefaultsKey) ?? ""
        collections = collectionStore.load()
        selectedCollectionID = collections.first?.id
        if !rootPath.isEmpty {
            statusMessage = "已恢复上次选择的目录"
            AppLogger.shared.info("Restored root path: \(rootPath)")
        }
    }

    var totalSelectedSize: Int64 {
        projects.reduce(0) { $0 + $1.selectedSize }
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file)
    }

    var selectedCollection: DirectoryCollection? {
        guard let selectedCollectionID else { return nil }
        return collections.first { $0.id == selectedCollectionID }
    }

    var selectedCollectionItemCount: Int {
        selectedCollection?.items.filter(\.isSelected).count ?? 0
    }

    var formattedSelectedCollectionSize: String {
        selectedCollection?.formattedSelectedSize ?? ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
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

    func isCalculatingSize(for project: ProjectInfo) -> Bool {
        guard isCalculatingSize else { return false }
        return project.dependencies.contains { !calculatedSizeDependencyIDs.contains($0.id) }
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
        if !rootPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: rootPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            UserDefaults.standard.set(rootPath, forKey: rootPathDefaultsKey)
            AppLogger.shared.info("Selected root path: \(rootPath)")
            Task { await scan() }
        }
    }

    func scanRestoredDirectoryIfNeeded() async {
        guard !hasPerformedInitialScan else { return }
        hasPerformedInitialScan = true
        guard !rootPath.isEmpty else { return }

        if FileManager.default.fileExists(atPath: rootPath) {
            await scan()
        } else {
            statusMessage = "上次选择的目录不存在，请重新选择"
            AppLogger.shared.error("Restored root path does not exist: \(rootPath)")
        }
    }

    func scan() async {
        await scan(forceRefreshSizes: false)
    }

    func forceRefresh() async {
        guard !rootPath.isEmpty else { return }
        await scan(forceRefreshSizes: true)
    }

    private func scan(forceRefreshSizes: Bool) async {
        guard !rootPath.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        isScanning = true
        statusMessage = forceRefreshSizes ? "正在强制刷新..." : "正在扫描项目..."
        lastError = nil
        AppLogger.shared.info("Scan started: \(rootPath), forceRefreshSizes=\(forceRefreshSizes)")

        let scannerCopy = scanner
        do {
            let scannedProjects = try await Task.detached {
                try scannerCopy.scanProjects(at: rootURL)
            }.value
            projects = scannedProjects
            statusMessage = "发现 \(projects.count) 个项目，\(totalDependencyCount) 个依赖目录。正在计算大小..."
            isScanning = false
            AppLogger.shared.info("Scan found \(projects.count) projects and \(totalDependencyCount) dependency directories")
            await calculateSizes(forceRefresh: forceRefreshSizes)
        } catch {
            lastError = "扫描失败: \(error.localizedDescription)"
            AppLogger.shared.error("Scan failed: \(error.localizedDescription)")
            isScanning = false
        }
    }

    func calculateSizes(forceRefresh: Bool = false) async {
        isCalculatingSize = true
        calculatedSizeDependencyIDs = []
        AppLogger.shared.info("Size calculation started, forceRefresh=\(forceRefresh)")

        struct SizeTask: Sendable {
            let projectID: String
            let depID: String
            let url: URL
            let modificationDate: Date?
        }

        var tasks: [SizeTask] = []
        for project in projects {
            for dep in project.dependencies {
                tasks.append(SizeTask(
                    projectID: project.id,
                    depID: dep.id,
                    url: dep.path,
                    modificationDate: dep.modificationDate
                ))
            }
        }

        let sizeCalcCopy = sizeCalc
        let sizeCacheCopy = sizeCache
        let total = tasks.count
        var cachedCount = 0
        for (idx, task) in tasks.enumerated() {
            let size: Int64
            if !forceRefresh,
               let cachedSize = sizeCache.cachedSize(for: task.url, modificationDate: task.modificationDate) {
                size = cachedSize
                cachedCount += 1
            } else {
                do {
                    size = try await Task.detached {
                        try sizeCalcCopy.directorySize(at: task.url)
                    }.value
                    sizeCacheCopy.store(
                        sizeInBytes: size,
                        for: task.url,
                        modificationDate: task.modificationDate
                    )
                } catch {
                    size = -1
                }
            }

            if let pi = projects.firstIndex(where: { $0.id == task.projectID }),
               let di = projects[pi].dependencies.firstIndex(where: { $0.id == task.depID }) {
                projects[pi].dependencies[di].sizeInBytes = size
                calculatedSizeDependencyIDs.insert(task.depID)
            }

            if (idx + 1) % 5 == 0 || idx == total - 1 {
                statusMessage = "正在计算大小... (\(idx + 1)/\(total))"
            }
        }

        applySorting()
        isCalculatingSize = false
        calculatedSizeDependencyIDs = []
        let cacheSuffix = cachedCount > 0 ? "，复用缓存 \(cachedCount) 项" : ""
        statusMessage = "扫描完成 — 共 \(projects.count) 个项目，\(totalDependencyCount) 个依赖项，总计 \(formattedTotalSize)\(cacheSuffix)"
        AppLogger.shared.info("Size calculation completed: \(totalDependencyCount) dependencies, \(formattedTotalSize), cached=\(cachedCount)")
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

    func beginCreateCollection() {
        guard selectedItemCount > 0 else { return }
        newCollectionName = defaultCollectionName()
        showCreateCollectionPrompt = true
    }

    func createCollectionFromSelected() {
        let selectedItems = projects.flatMap { project in
            project.dependencies.filter(\.isSelected).map(DirectoryCollectionItem.init(dependency:))
        }
        guard !selectedItems.isEmpty else { return }

        let dedupedItems = Array(
            Dictionary(grouping: selectedItems, by: \.path)
                .compactMap { $0.value.first }
        )
        .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

        let trimmedName = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = DirectoryCollection(
            name: trimmedName.isEmpty ? defaultCollectionName() : trimmedName,
            items: dedupedItems
        )
        collections.append(collection)
        selectedCollectionID = collection.id
        persistCollections()
        showCollections = true
        statusMessage = "已收集 \(collection.items.count) 个目录到「\(collection.name)」"
        AppLogger.shared.info("Created directory collection: \(collection.name), items=\(collection.items.count)")
    }

    func selectCollection(_ collectionID: UUID) {
        selectedCollectionID = collectionID
    }

    func toggleCollectionItem(_ itemID: String) {
        guard let ci = selectedCollectionIndex(),
              let ii = collections[ci].items.firstIndex(where: { $0.id == itemID })
        else { return }
        collections[ci].items[ii].isSelected.toggle()
        collections[ci].updatedAt = Date()
        persistCollections()
    }

    func setAllCollectionItems(selected: Bool) {
        guard let ci = selectedCollectionIndex() else { return }
        for i in collections[ci].items.indices {
            collections[ci].items[i].isSelected = selected
        }
        collections[ci].updatedAt = Date()
        persistCollections()
    }

    func confirmDeleteSelectedCollection() {
        guard selectedCollection != nil else { return }
        showCollectionDeleteConfirmation = true
    }

    func deleteSelectedCollection() {
        guard let ci = selectedCollectionIndex() else { return }
        let removedName = collections[ci].name
        collections.remove(at: ci)
        selectedCollectionID = collections.first?.id
        persistCollections()
        statusMessage = "已删除集合「\(removedName)」"
    }

    func confirmRemoveSelectedCollectionItems() {
        guard selectedCollectionItemCount > 0 else { return }
        showCollectionItemsRemoveConfirmation = true
    }

    func removeSelectedCollectionItems() {
        guard let ci = selectedCollectionIndex() else { return }
        let count = collections[ci].items.filter(\.isSelected).count
        collections[ci].items.removeAll(where: \.isSelected)
        collections[ci].updatedAt = Date()
        persistCollections()
        statusMessage = "已从集合移除 \(count) 个条目"
    }

    func confirmRemoveSelectedCollectionDirectories() {
        guard selectedCollectionItemCount > 0 else { return }
        showCollectionDirectoriesRemoveConfirmation = true
    }

    func removeSelected() async {
        isRemoving = true
        statusMessage = "正在删除..."
        let itemsToRemove = projects.flatMap { $0.dependencies.filter({ $0.isSelected }) }
        AppLogger.shared.info("Remove started: \(itemsToRemove.count) selected dependency directories")

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
            sizeCache.remove(paths: removedPaths)

            statusMessage = "已删除 \(removed.count) 个依赖目录"
            AppLogger.shared.info("Remove completed: \(removed.count) dependency directories")
        } catch {
            lastError = "删除失败: \(error.localizedDescription)"
            AppLogger.shared.error("Remove failed: \(error.localizedDescription)")
        }
        isRemoving = false
    }

    func removeSelectedCollectionDirectories() async {
        guard let collection = selectedCollection else { return }
        isRemoving = true
        statusMessage = "正在按集合删除..."
        let pathsToRemove = collection.selectedItems.map(\.path)
        AppLogger.shared.info("Collection remove started: \(collection.name), paths=\(pathsToRemove.count)")

        let cleanerCopy = cleaner
        do {
            let removed = try await Task.detached {
                try cleanerCopy.remove(paths: pathsToRemove)
            }.value
            let removedPaths = Set(removed.map(\.path))

            for i in projects.indices {
                projects[i].dependencies.removeAll { removedPaths.contains($0.path.path) }
            }
            projects.removeAll { $0.dependencies.isEmpty }
            sizeCache.remove(paths: removedPaths)
            markRemovedCollectionPaths(removedPaths)

            statusMessage = "集合「\(collection.name)」已尝试 \(pathsToRemove.count) 项，删除 \(removed.count) 项"
            AppLogger.shared.info("Collection remove completed: attempted=\(pathsToRemove.count), removed=\(removed.count)")
        } catch {
            lastError = "集合删除失败: \(error.localizedDescription)"
            AppLogger.shared.error("Collection remove failed: \(error.localizedDescription)")
        }
        isRemoving = false
    }

    func collectionItemExists(_ item: DirectoryCollectionItem) -> Bool {
        FileManager.default.fileExists(atPath: item.path)
    }

    private func selectedCollectionIndex() -> Int? {
        guard let selectedCollectionID else { return nil }
        return collections.firstIndex { $0.id == selectedCollectionID }
    }

    private func persistCollections() {
        collectionStore.save(collections)
    }

    private func markRemovedCollectionPaths(_ removedPaths: Set<String>) {
        guard !removedPaths.isEmpty,
              let ci = selectedCollectionIndex()
        else { return }

        for i in collections[ci].items.indices where removedPaths.contains(collections[ci].items[i].path) {
            collections[ci].items[i].isSelected = false
        }
        collections[ci].updatedAt = Date()
        persistCollections()
    }

    private func defaultCollectionName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "收集 \(formatter.string(from: Date()))"
    }
}
