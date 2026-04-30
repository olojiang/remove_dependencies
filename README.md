# DevCleaner — 开发依赖清理工具

macOS 原生桌面应用，帮助你批量扫描和清理开发项目中的依赖目录（如 `node_modules`、`.venv`、`dist` 等），释放磁盘空间。

## 功能特性

- **一键扫描** — 选择工作区根目录，自动发现所有开发项目
- **智能识别** — 通过 `package.json`、`Cargo.toml`、`.git` 等 16 种标识判断项目类型
- **依赖检测** — 检测 16 种常见依赖/构建产物目录：

  | 类型 | 目录名 | 关联技术 |
  |------|--------|----------|
  | 包依赖 | `node_modules` | Node.js |
  | 虚拟环境 | `.venv` / `venv` / `env` | Python |
  | 构建产物 | `dist` / `build` | 通用 |
  | 框架缓存 | `.next` / `.nuxt` | Next.js / Nuxt.js |
  | 编译产物 | `target` | Rust / Java |
  | CocoaPods | `Pods` | iOS / macOS |
  | 字节码缓存 | `__pycache__` | Python |
  | 构建工具 | `.gradle` | Gradle |
  | 依赖供应 | `vendor` | Go / PHP |
  | Dart 工具 | `.dart_tool` / `.pub-cache` | Dart / Flutter |
  | 通用缓存 | `.cache` | 各种工具 |

- **递归扫描** — 深度遍历子目录，找出 monorepo 中嵌套的 node_modules 等
- **树状展示** — 按项目分组，显示相对路径，支持展开/折叠
- **精确统计** — 自动计算每个依赖目录的真实大小（含隐藏文件，兼容 pnpm）
- **排序功能** — 支持按名称/大小/修改时间排序，正序/逆序切换
- **批量操作** — 多选、按项目全选、全局全选/取消
- **安全删除** — 删除前有确认对话框，显示将释放的空间大小

## 环境要求

- macOS 14.0 (Sonoma) 或更高版本
- Swift 5.9+ (已内置于 Xcode Command Line Tools)

安装 Command Line Tools（如果还没有）：

```bash
xcode-select --install
```

## 快速开始

### 构建并运行

```bash
git clone <repo-url>
cd remove_dependencies
bash build.sh
```

`build.sh` 会自动完成三步：
1. 编译 Swift 源码
2. 打包为 `DevCleaner.app` 应用包
3. 启动应用

### 手动构建

```bash
# 编译
swift build --product DevCleaner

# 运行（不打包为 .app）
.build/arm64-apple-macosx/debug/DevCleaner
```

## 使用方法

1. **启动应用** — 运行 `bash build.sh`
2. **选择目录** — 点击右上角的「选择目录」按钮，选择你的工作区根目录（如 `~/Workspace`）
3. **等待扫描** — 应用会扫描该目录下所有子目录，找出开发项目和依赖目录，并自动计算大小
4. **选择要删除的依赖** — 在树状列表中：
   - 点击复选框选择单个依赖项
   - 点击项目行的复选框一次性选中该项目下所有依赖
   - 使用底栏的「全选」/「取消全选」按钮批量操作
5. **确认删除** — 点击底栏的「删除选中」按钮，确认对话框会显示将释放多少空间
6. **重新安装** — 删除后如果需要，进入对应项目目录运行 `npm install` / `pip install` 等重新安装

## 运行测试

```bash
swift run DevCleanerTests
```

测试覆盖三个核心服务（共 23 个测试）：
- `DirectoryScanner` — 项目识别、递归依赖扫描、相对路径、多语言支持（15 个测试）
- `SizeCalculator` — 目录大小递归计算、隐藏文件计算、修改时间（5 个测试）
- `DependencyCleaner` — 依赖删除与异常处理（3 个测试）

## 项目结构

```
Sources/
├── DevCleaner/                  # 核心库 (DevCleanerLib)
│   ├── Models/
│   │   ├── DependencyType.swift   # 依赖类型枚举（16 种）
│   │   ├── DependencyItem.swift   # 依赖项数据模型
│   │   └── ProjectInfo.swift      # 项目数据模型
│   └── Services/
│       ├── DirectoryScanner.swift  # 目录扫描服务
│       ├── SizeCalculator.swift    # 大小计算服务
│       └── DependencyCleaner.swift # 清理服务
├── DevCleanerApp/               # SwiftUI 应用
│   ├── App.swift                  # 应用入口
│   ├── ContentView.swift          # 主视图
│   └── ScannerViewModel.swift     # 视图模型 (MVVM)
├── TestKit/                     # 轻量测试框架
└── DevCleanerTests/             # 测试用例（17 个）
```

## 技术栈

- **语言**: Swift 6
- **UI**: SwiftUI (macOS 原生)
- **架构**: MVVM
- **构建**: Swift Package Manager
- **测试**: 自定义 TestKit（兼容纯 Command Line Tools 环境）
