import Foundation
import AppKit
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
    @Published var showAdminPasswordPrompt: Bool = false
    @Published var adminPasswordInput: String = ""
    @Published var adminPasswordStatusMessage: String?
    @Published var hasStoredAdminPassword: Bool = false
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
    private let adminPasswordStore = AdminPasswordStore()
    private let rootPathDefaultsKey = "lastSelectedRootPath"
    private var hasPerformedInitialScan = false
    private var dependencySelectionAnchorID: String?
    private var dependencyShiftSelectionSnapshot: [String: Bool]?
    private var collectionSelectionAnchorID: String?
    private var collectionShiftSelectionSnapshot: [String: Bool]?
    private var pendingPrivilegedRemoval: PendingPrivilegedRemoval?

    private enum PendingPrivilegedRemoval {
        case dependencies([String])
        case collectionDirectories([String], collectionName: String)
    }

    init() {
        rootPath = UserDefaults.standard.string(forKey: rootPathDefaultsKey) ?? ""
        collections = collectionStore.load()
        selectedCollectionID = collections.first?.id
        hasStoredAdminPassword = adminPasswordStore.hasPassword()
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

        resetDependencySelectionTracking()
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
        resetDependencySelectionTracking()
        for j in projects[idx].dependencies.indices {
            projects[idx].dependencies[j].isSelected = selected
        }
    }

    func toggleDependency(projectID: String, depID: String, extendingRange: Bool = false) {
        if extendingRange, let anchorID = dependencySelectionAnchorID {
            selectDependencyRange(from: anchorID, to: depID)
            return
        }

        guard let pi = projects.firstIndex(where: { $0.id == projectID }),
              let di = projects[pi].dependencies.firstIndex(where: { $0.id == depID })
        else { return }
        resetDependencyRangeSelection()
        projects[pi].dependencies[di].isSelected.toggle()
        dependencySelectionAnchorID = depID
    }

    func toggleExpand(_ projectID: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].isExpanded.toggle()
    }

    func expandAllProjects() {
        guard !projects.isEmpty else { return }
        for i in projects.indices {
            projects[i].isExpanded = true
        }
    }

    func collapseAllProjects() {
        guard !projects.isEmpty else { return }
        for i in projects.indices {
            projects[i].isExpanded = false
        }
        finishRangeSelection()
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        statusMessage = "已复制路径: \(url.path)"
    }

    func openInTerminal(_ url: URL) {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", url.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                lastError = "无法在 Terminal 打开: \(url.path)"
                AppLogger.shared.error("Open in Terminal failed: \(url.path), status=\(process.terminationStatus)")
                return
            }
            statusMessage = "已在 Terminal 打开: \(url.path)"
        } catch {
            lastError = "无法在 Terminal 打开: \(error.localizedDescription)"
            AppLogger.shared.error("Open in Terminal failed: \(url.path), \(error.localizedDescription)")
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "已在 Finder 中定位: \(url.path)"
    }

    func selectAll() {
        resetDependencySelectionTracking()
        for i in projects.indices {
            for j in projects[i].dependencies.indices {
                projects[i].dependencies[j].isSelected = true
            }
        }
    }

    func deselectAll() {
        resetDependencySelectionTracking()
        for i in projects.indices {
            for j in projects[i].dependencies.indices {
                projects[i].dependencies[j].isSelected = false
            }
        }
    }

    func finishRangeSelection() {
        resetDependencyRangeSelection()
        resetCollectionRangeSelection()
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
        resetCollectionSelectionTracking()
        selectedCollectionID = collectionID
    }

    func toggleCollectionItem(_ itemID: String, extendingRange: Bool = false) {
        if extendingRange, let anchorID = collectionSelectionAnchorID {
            selectCollectionRange(from: anchorID, to: itemID)
            return
        }

        guard let ci = selectedCollectionIndex(),
              let ii = collections[ci].items.firstIndex(where: { $0.id == itemID })
        else { return }
        resetCollectionRangeSelection()
        collections[ci].items[ii].isSelected.toggle()
        collectionSelectionAnchorID = itemID
        collections[ci].updatedAt = Date()
        persistCollections()
    }

    func setAllCollectionItems(selected: Bool) {
        guard let ci = selectedCollectionIndex() else { return }
        resetCollectionSelectionTracking()
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
        resetCollectionSelectionTracking()
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

    func beginAdminPasswordEntry() {
        adminPasswordInput = ""
        adminPasswordStatusMessage = hasStoredAdminPassword
            ? "已保存管理员密码。重新输入可更新，或删除已保存密码。"
            : nil
        showAdminPasswordPrompt = true
    }

    func cancelAdminPasswordPrompt() {
        adminPasswordInput = ""
        adminPasswordStatusMessage = nil
        pendingPrivilegedRemoval = nil
    }

    func saveAdminPassword() async {
        let password = adminPasswordInput
        guard !password.isEmpty else {
            adminPasswordStatusMessage = "请输入管理员密码"
            return
        }

        adminPasswordStatusMessage = "正在验证管理员密码..."
        do {
            try await Task.detached {
                try AdminPasswordStore.validateSudoPassword(password)
            }.value
            try adminPasswordStore.savePassword(password)
            hasStoredAdminPassword = true
            adminPasswordInput = ""
            showAdminPasswordPrompt = false
            adminPasswordStatusMessage = nil
            statusMessage = "管理员密码已保存到钥匙串"

            if let pendingPrivilegedRemoval {
                self.pendingPrivilegedRemoval = nil
                switch pendingPrivilegedRemoval {
                case .dependencies(let paths):
                    await removeDependencyPaths(paths, promptForPasswordOnFailure: false)
                case .collectionDirectories(let paths, let collectionName):
                    await removeCollectionPaths(paths, collectionName: collectionName, promptForPasswordOnFailure: false)
                }
            }
        } catch {
            adminPasswordStatusMessage = "验证失败: \(error.localizedDescription)"
            AppLogger.shared.error("Admin password validation failed: \(error.localizedDescription)")
        }
    }

    func forgetAdminPassword() {
        do {
            try adminPasswordStore.deletePassword()
            hasStoredAdminPassword = false
            adminPasswordInput = ""
            adminPasswordStatusMessage = "已删除钥匙串中的管理员密码"
            statusMessage = "已删除保存的管理员密码"
        } catch {
            adminPasswordStatusMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    func removeSelected() async {
        let pathsToRemove = projects
            .flatMap { $0.dependencies.filter(\.isSelected) }
            .map(\.path.path)
        await removeDependencyPaths(pathsToRemove, promptForPasswordOnFailure: true)
    }

    func removeSelectedCollectionDirectories() async {
        guard let collection = selectedCollection else { return }
        await removeCollectionPaths(
            collection.selectedItems.map(\.path),
            collectionName: collection.name,
            promptForPasswordOnFailure: true
        )
    }

    func collectionItemExists(_ item: DirectoryCollectionItem) -> Bool {
        FileManager.default.fileExists(atPath: item.path)
    }

    private func removeDependencyPaths(_ pathsToRemove: [String], promptForPasswordOnFailure: Bool) async {
        guard !pathsToRemove.isEmpty else { return }
        isRemoving = true
        statusMessage = "正在删除..."
        AppLogger.shared.info("Remove started: \(pathsToRemove.count) selected dependency directories")

        let cleanerCopy = cleaner
        let password = storedAdminPasswordForDeletion()
        let result = await Task.detached {
            cleanerCopy.removeWithElevatedFallback(paths: pathsToRemove, password: password)
        }.value
        let removedPaths = Set(result.removed.map(\.path))

        applyRemovedDependencyPaths(removedPaths)

        if result.failed.isEmpty {
            statusMessage = "已删除 \(result.removed.count) 个依赖目录"
            AppLogger.shared.info("Remove completed: \(result.removed.count) dependency directories")
        } else if promptForPasswordOnFailure {
            pendingPrivilegedRemoval = .dependencies(result.failed.map(\.path.path))
            adminPasswordInput = ""
            adminPasswordStatusMessage = password == nil
                ? "有 \(result.failed.count) 个目录需要管理员权限。输入管理员密码后会自动重试。"
                : "已保存的管理员密码未能删除 \(result.failed.count) 个目录。重新输入后会自动重试。"
            showAdminPasswordPrompt = true
            statusMessage = "已删除 \(result.removed.count) 个，\(result.failed.count) 个需要管理员权限"
            AppLogger.shared.info("Remove needs elevated retry: failed=\(result.failed.count)")
        } else {
            statusMessage = "已删除 \(result.removed.count) 个，\(result.failed.count) 个失败"
            lastError = failureSummary(title: "删除失败", failures: result.failed)
            AppLogger.shared.error("Remove failed paths: \(result.failed.count)")
        }

        isRemoving = false
    }

    private func removeCollectionPaths(
        _ pathsToRemove: [String],
        collectionName: String,
        promptForPasswordOnFailure: Bool
    ) async {
        guard !pathsToRemove.isEmpty else { return }
        isRemoving = true
        statusMessage = "正在按集合删除..."
        AppLogger.shared.info("Collection remove started: \(collectionName), paths=\(pathsToRemove.count)")

        let cleanerCopy = cleaner
        let password = storedAdminPasswordForDeletion()
        let result = await Task.detached {
            cleanerCopy.removeWithElevatedFallback(paths: pathsToRemove, password: password)
        }.value
        let removedPaths = Set(result.removed.map(\.path))

        applyRemovedDependencyPaths(removedPaths)
        markRemovedCollectionPaths(removedPaths)

        if result.failed.isEmpty {
            statusMessage = "集合「\(collectionName)」已尝试 \(pathsToRemove.count) 项，删除 \(result.removed.count) 项"
            AppLogger.shared.info("Collection remove completed: attempted=\(pathsToRemove.count), removed=\(result.removed.count)")
        } else if promptForPasswordOnFailure {
            pendingPrivilegedRemoval = .collectionDirectories(result.failed.map(\.path.path), collectionName: collectionName)
            adminPasswordInput = ""
            adminPasswordStatusMessage = password == nil
                ? "集合中有 \(result.failed.count) 个目录需要管理员权限。输入管理员密码后会自动重试。"
                : "已保存的管理员密码未能删除集合中的 \(result.failed.count) 个目录。重新输入后会自动重试。"
            showAdminPasswordPrompt = true
            statusMessage = "集合「\(collectionName)」已删除 \(result.removed.count) 个，\(result.failed.count) 个需要管理员权限"
            AppLogger.shared.info("Collection remove needs elevated retry: failed=\(result.failed.count)")
        } else {
            statusMessage = "集合「\(collectionName)」已删除 \(result.removed.count) 个，\(result.failed.count) 个失败"
            lastError = failureSummary(title: "集合删除失败", failures: result.failed)
            AppLogger.shared.error("Collection remove failed paths: \(result.failed.count)")
        }

        isRemoving = false
    }

    private func storedAdminPasswordForDeletion() -> String? {
        do {
            return try adminPasswordStore.loadPassword()
        } catch {
            lastError = "读取管理员密码失败: \(error.localizedDescription)"
            AppLogger.shared.error("Admin password load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func applyRemovedDependencyPaths(_ removedPaths: Set<String>) {
        guard !removedPaths.isEmpty else { return }
        for i in projects.indices {
            projects[i].dependencies.removeAll { removedPaths.contains($0.path.path) }
        }
        projects.removeAll { $0.dependencies.isEmpty }
        sizeCache.remove(paths: removedPaths)
    }

    private func failureSummary(title: String, failures: [RemovalFailure]) -> String {
        let examples = failures.prefix(3).map { failure in
            "\(failure.path.path): \(failure.message)"
        }.joined(separator: "\n")
        let suffix = failures.count > 3 ? "\n其余 \(failures.count - 3) 项略。" : ""
        return "\(title): \(failures.count) 个目录未删除。\n\(examples)\(suffix)"
    }

    private func selectedCollectionIndex() -> Int? {
        guard let selectedCollectionID else { return nil }
        return collections.firstIndex { $0.id == selectedCollectionID }
    }

    private func resetDependencyRangeSelection() {
        dependencyShiftSelectionSnapshot = nil
    }

    private func resetDependencySelectionTracking() {
        dependencySelectionAnchorID = nil
        dependencyShiftSelectionSnapshot = nil
    }

    private func resetCollectionRangeSelection() {
        collectionShiftSelectionSnapshot = nil
    }

    private func resetCollectionSelectionTracking() {
        collectionSelectionAnchorID = nil
        collectionShiftSelectionSnapshot = nil
    }

    private func dependencySelectionState() -> [String: Bool] {
        Dictionary(
            uniqueKeysWithValues: projects.flatMap { project in
                project.dependencies.map { ($0.id, $0.isSelected) }
            }
        )
    }

    private func applyDependencySelectionState(_ state: [String: Bool]) {
        for pi in projects.indices {
            for di in projects[pi].dependencies.indices {
                let id = projects[pi].dependencies[di].id
                projects[pi].dependencies[di].isSelected = state[id] ?? false
            }
        }
    }

    private func selectDependencyRange(from anchorID: String, to targetID: String) {
        let orderedIDs = projects.flatMap { project in
            project.isExpanded ? project.dependencies.map(\.id) : []
        }
        guard let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID)
        else {
            guard let pi = projects.firstIndex(where: { project in
                project.dependencies.contains { $0.id == targetID }
            }), let di = projects[pi].dependencies.firstIndex(where: { $0.id == targetID }) else { return }
            resetDependencyRangeSelection()
            projects[pi].dependencies[di].isSelected.toggle()
            dependencySelectionAnchorID = targetID
            return
        }

        if dependencyShiftSelectionSnapshot == nil {
            dependencyShiftSelectionSnapshot = dependencySelectionState()
        }

        applyDependencySelectionState(dependencyShiftSelectionSnapshot ?? [:])
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let selectedIDs = Set(orderedIDs[bounds])
        for pi in projects.indices {
            for di in projects[pi].dependencies.indices where selectedIDs.contains(projects[pi].dependencies[di].id) {
                projects[pi].dependencies[di].isSelected = true
            }
        }
    }

    private func collectionSelectionState(collectionIndex ci: Int) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: collections[ci].items.map { ($0.id, $0.isSelected) })
    }

    private func applyCollectionSelectionState(_ state: [String: Bool], collectionIndex ci: Int) {
        for ii in collections[ci].items.indices {
            let id = collections[ci].items[ii].id
            collections[ci].items[ii].isSelected = state[id] ?? false
        }
    }

    private func selectCollectionRange(from anchorID: String, to targetID: String) {
        guard let ci = selectedCollectionIndex() else { return }
        let orderedIDs = collections[ci].items.map(\.id)
        guard let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID)
        else {
            resetCollectionRangeSelection()
            collectionSelectionAnchorID = targetID
            return
        }

        if collectionShiftSelectionSnapshot == nil {
            collectionShiftSelectionSnapshot = collectionSelectionState(collectionIndex: ci)
        }

        applyCollectionSelectionState(collectionShiftSelectionSnapshot ?? [:], collectionIndex: ci)
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let selectedIDs = Set(orderedIDs[bounds])
        for ii in collections[ci].items.indices where selectedIDs.contains(collections[ci].items[ii].id) {
            collections[ci].items[ii].isSelected = true
        }
        collections[ci].updatedAt = Date()
        persistCollections()
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
