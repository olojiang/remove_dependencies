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
        .alert("错误", isPresented: .init(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("确定") { vm.lastError = nil }
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("DevCleaner")
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

                if !vm.rootPath.isEmpty {
                    Button {
                        Task { await vm.scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新扫描")
                    .disabled(vm.isScanning)
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

            if vm.isCalculatingSize {
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
