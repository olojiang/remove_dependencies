import SwiftUI
import DevCleanerLib

struct ContentView: View {
    @StateObject private var vm = ScannerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if vm.projects.isEmpty && !vm.isScanning {
                emptyState
            } else {
                if !vm.projects.isEmpty {
                    sortBar
                    Divider()
                }
                projectList
            }
            Divider()
            bottomBar
        }
        .alert("删除确认", isPresented: $vm.showRemoveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await vm.removeSelected() }
            }
        } message: {
            Text("确定要删除选中的 \(vm.selectedItemCount) 个依赖目录吗？\n将释放约 \(vm.formattedSelectedSize) 空间。\n此操作不可撤销。")
        }
        .alert("创建收集", isPresented: $vm.showCreateCollectionPrompt) {
            TextField("收集名称", text: $vm.newCollectionName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                vm.createCollectionFromSelected()
            }
        } message: {
            Text("将当前选中的 \(vm.selectedItemCount) 个目录保存为一个可重复执行的路径集合。")
        }
        .alert("错误", isPresented: .init(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("确定") { vm.lastError = nil }
        } message: {
            Text(vm.lastError ?? "")
        }
        .task {
            await vm.scanRestoredDirectoryIfNeeded()
        }
        .sheet(isPresented: $vm.showCollections) {
            CollectionListView(vm: vm)
                .frame(minWidth: 900, minHeight: 520)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("DevCleaner 纪")
                    .font(.headline)
                Text("开发依赖清理工具")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(vm.rootPath.isEmpty ? "未选择目录" : vm.rootPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .foregroundStyle(vm.rootPath.isEmpty ? .secondary : .primary)

                Button("选择目录") {
                    vm.selectDirectory()
                }
                .controlSize(.regular)

                Button {
                    vm.showCollections = true
                } label: {
                    Label("集合列表", systemImage: "tray.full")
                }
                .controlSize(.regular)

                if !vm.rootPath.isEmpty {
                    Button {
                        Task { await vm.forceRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("强制刷新：重新扫描并重新计算所有大小")
                    .disabled(vm.isScanning || vm.isCalculatingSize)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 16) {
            projectSortSection
            Divider().frame(height: 18)
            depSortSection
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .onChange(of: vm.projectSortField) { vm.applySorting() }
        .onChange(of: vm.depSortField) { vm.applySorting() }
    }

    private var projectSortSection: some View {
        HStack(spacing: 6) {
            Text("项目排序:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $vm.projectSortField) {
                ForEach(SortField.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                vm.projectSortOrder = vm.projectSortOrder == .ascending ? .descending : .ascending
                vm.applySorting()
            } label: {
                Image(systemName: vm.projectSortOrder == .ascending ? "arrow.up" : "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private var depSortSection: some View {
        HStack(spacing: 6) {
            Text("依赖排序:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $vm.depSortField) {
                ForEach(SortField.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                vm.depSortOrder = vm.depSortOrder == .ascending ? .descending : .ascending
                vm.applySorting()
            } label: {
                Image(systemName: vm.depSortOrder == .ascending ? "arrow.up" : "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("选择一个工作区目录开始扫描")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("将递归分析该目录下的所有开发项目，\n找出 node_modules、.venv、dist 等依赖目录")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Project List

    private var projectList: some View {
        ScrollView {
            if vm.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在扫描...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            } else {
                LazyVStack(spacing: 4, pinnedViews: []) {
                    ForEach(vm.projects.indices, id: \.self) { pi in
                        projectSection(index: pi)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func projectSection(index pi: Int) -> some View {
        let project = vm.projects[pi]
        return VStack(spacing: 0) {
            projectHeader(project: project, index: pi)
            if project.isExpanded {
                ForEach(project.dependencies.indices, id: \.self) { di in
                    dependencyRow(project: project, depIndex: di)
                    if di < project.dependencies.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .padding(.horizontal, 8)
    }

    private func projectHeader(project: ProjectInfo, index pi: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                vm.toggleExpand(project.id)
            } label: {
                Image(systemName: project.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            let allSelected = !project.dependencies.isEmpty &&
                project.dependencies.allSatisfy({ $0.isSelected })
            let someSelected = project.dependencies.contains(where: { $0.isSelected })

            Toggle(isOn: Binding(
                get: { allSelected },
                set: { vm.toggleProject(project.id, selected: $0) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .opacity(someSelected && !allSelected ? 0.5 : 1)

            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

            Text(project.name)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            Spacer()

            Text("\(project.dependencies.count) 个依赖")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.blue.opacity(0.12)))
                .foregroundStyle(.blue)

            Text(project.formattedTotalSize)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(sizeColor(project.totalSize))
                .fontWeight(.medium)
                .frame(width: 80, alignment: .trailing)

            if vm.isCalculatingSize(for: project) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleExpand(project.id)
        }
    }

    private func dependencyRow(project: ProjectInfo, depIndex di: Int) -> some View {
        let dep = project.dependencies[di]
        return HStack(spacing: 8) {
            Spacer().frame(width: 24)

            Toggle(isOn: Binding(
                get: { dep.isSelected },
                set: { _ in vm.toggleDependency(projectID: project.id, depID: dep.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)

            Image(systemName: depIcon(for: dep.type))
                .foregroundStyle(depColor(for: dep.type))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(dep.relativePath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(dep.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(dep.formattedDate)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Text(dep.formattedSize)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(sizeColor(dep.sizeInBytes))
                .fontWeight(.medium)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(dep.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleDependency(projectID: project.id, depID: dep.id)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if vm.isRemoving {
                ProgressView()
                    .controlSize(.small)
            }
            if vm.isCalculatingSize {
                ProgressView()
                    .controlSize(.small)
            }

            Text(vm.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if !vm.projects.isEmpty {
                Button("全选") { vm.selectAll() }
                    .controlSize(.small)
                Button("取消全选") { vm.deselectAll() }
                    .controlSize(.small)

                Divider().frame(height: 20)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("已选 \(vm.selectedItemCount) / \(vm.totalDependencyCount) 项")
                        .font(.caption)
                    Text(vm.formattedSelectedSize)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                }

                Button {
                    vm.beginCreateCollection()
                } label: {
                    Label("收集", systemImage: "plus.rectangle.on.folder")
                }
                .disabled(vm.selectedItemCount == 0 || vm.isRemoving)
                .controlSize(.regular)

                Button(role: .destructive) {
                    vm.confirmRemove()
                } label: {
                    Label("删除选中", systemImage: "trash")
                }
                .disabled(vm.selectedItemCount == 0 || vm.isRemoving)
                .controlSize(.regular)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Helpers

    private func depIcon(for type: DependencyType) -> String {
        switch type {
        case .nodeModules: return "shippingbox.fill"
        case .pythonVenv, .pythonVenvAlt, .pythonEnv: return "globe"
        case .dist, .build, .nextjs, .nuxtjs: return "hammer.fill"
        case .target: return "scope"
        case .pods: return "leaf.fill"
        case .pycache: return "memorychip"
        case .gradle: return "gearshape.2.fill"
        case .vendor: return "archivebox.fill"
        case .dartTool, .pubCache: return "cube.fill"
        case .dotCache: return "clock.fill"
        }
    }

    private func depColor(for type: DependencyType) -> Color {
        switch type {
        case .nodeModules: return .green
        case .pythonVenv, .pythonVenvAlt, .pythonEnv: return .blue
        case .dist, .build, .nextjs, .nuxtjs: return .orange
        case .target: return .red
        case .pods: return .mint
        case .pycache: return .purple
        case .gradle: return .teal
        case .vendor: return .indigo
        case .dartTool, .pubCache: return .cyan
        case .dotCache: return .gray
        }
    }

    private func sizeColor(_ size: Int64) -> Color {
        if size > 500_000_000 { return .red }
        if size > 100_000_000 { return .orange }
        if size > 10_000_000 { return .yellow }
        return .secondary
    }
}

private struct CollectionListView: View {
    @ObservedObject var vm: ScannerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full")
                    .foregroundStyle(.blue)
                Text("集合列表")
                    .font(.headline)
                Spacer()
                Button {
                    vm.showCollections = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                collectionSidebar
                    .frame(width: 260)

                Divider()

                collectionDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("删除集合", isPresented: $vm.showCollectionDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                vm.deleteSelectedCollection()
            }
        } message: {
            Text("仅删除集合记录，不会删除磁盘目录。")
        }
        .alert("移除集合条目", isPresented: $vm.showCollectionItemsRemoveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                vm.removeSelectedCollectionItems()
            }
        } message: {
            Text("将选中的 \(vm.selectedCollectionItemCount) 个路径从集合中移除，不会删除磁盘目录。")
        }
        .alert("按集合删除目录", isPresented: $vm.showCollectionDirectoriesRemoveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除目录", role: .destructive) {
                Task { await vm.removeSelectedCollectionDirectories() }
            }
        } message: {
            Text("将尝试删除集合中已勾选的 \(vm.selectedCollectionItemCount) 个目录，约 \(vm.formattedSelectedCollectionSize)。不存在的路径会跳过，此操作可重复执行。")
        }
    }

    private var collectionSidebar: some View {
        VStack(spacing: 0) {
            if vm.collections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("暂无集合")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(vm.collections) { collection in
                            Button {
                                vm.selectCollection(collection.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name)
                                            .font(.system(.body, design: .rounded))
                                            .lineLimit(1)
                                        Text("\(collection.items.count) 个路径")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(collection.id == vm.selectedCollectionID
                                              ? Color.accentColor.opacity(0.14)
                                              : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    vm.confirmDeleteSelectedCollection()
                } label: {
                    Label("删除集合", systemImage: "trash")
                }
                .disabled(vm.selectedCollection == nil)
                Spacer()
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var collectionDetail: some View {
        VStack(spacing: 0) {
            if let collection = vm.selectedCollection {
                collectionToolbar(collection)
                Divider()
                collectionItems(collection)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("选择一个集合查看目录列表")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func collectionToolbar(_ collection: DirectoryCollection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("已选 \(vm.selectedCollectionItemCount) / \(collection.items.count) 项  \(vm.formattedSelectedCollectionSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("全选") {
                vm.setAllCollectionItems(selected: true)
            }
            .controlSize(.small)

            Button("取消全选") {
                vm.setAllCollectionItems(selected: false)
            }
            .controlSize(.small)

            Button(role: .destructive) {
                vm.confirmRemoveSelectedCollectionItems()
            } label: {
                Label("移除条目", systemImage: "minus.circle")
            }
            .disabled(vm.selectedCollectionItemCount == 0)

            Button(role: .destructive) {
                vm.confirmRemoveSelectedCollectionDirectories()
            } label: {
                Label("删除目录", systemImage: "trash")
            }
            .disabled(vm.selectedCollectionItemCount == 0 || vm.isRemoving)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func collectionItems(_ collection: DirectoryCollection) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(collection.items) { item in
                    collectionItemRow(item)
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func collectionItemRow(_ item: DirectoryCollectionItem) -> some View {
        let exists = vm.collectionItemExists(item)
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { item.isSelected },
                set: { _ in vm.toggleCollectionItem(item.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)

            Image(systemName: exists ? "folder.fill" : "folder.badge.questionmark")
                .foregroundStyle(exists ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.relativePath) · \(item.typeName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(exists ? "存在" : "不存在")
                .font(.caption2)
                .foregroundStyle(exists ? .green : .secondary)
                .frame(width: 46, alignment: .trailing)

            Text(item.formattedSize)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(sizeColor(item.sizeInBytes))
                .fontWeight(.medium)
                .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(item.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleCollectionItem(item.id)
        }
    }

    private func sizeColor(_ size: Int64) -> Color {
        if size > 500_000_000 { return .red }
        if size > 100_000_000 { return .orange }
        if size > 10_000_000 { return .yellow }
        return .secondary
    }
}
