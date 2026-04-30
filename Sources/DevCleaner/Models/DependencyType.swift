import Foundation

public enum DependencyType: String, CaseIterable, Identifiable, Sendable {
    case nodeModules = "node_modules"
    case pythonVenv = ".venv"
    case pythonVenvAlt = "venv"
    case pythonEnv = "env"
    case dist = "dist"
    case build = "build"
    case nextjs = ".next"
    case nuxtjs = ".nuxt"
    case target = "target"
    case pods = "Pods"
    case pycache = "__pycache__"
    case gradle = ".gradle"
    case vendor = "vendor"
    case dartTool = ".dart_tool"
    case pubCache = ".pub-cache"
    case dotCache = ".cache"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nodeModules: return "node_modules (Node.js)"
        case .pythonVenv: return ".venv (Python)"
        case .pythonVenvAlt: return "venv (Python)"
        case .pythonEnv: return "env (Python)"
        case .dist: return "dist (构建产物)"
        case .build: return "build (构建产物)"
        case .nextjs: return ".next (Next.js)"
        case .nuxtjs: return ".nuxt (Nuxt.js)"
        case .target: return "target (Rust/Java)"
        case .pods: return "Pods (CocoaPods)"
        case .pycache: return "__pycache__ (Python)"
        case .gradle: return ".gradle (Gradle)"
        case .vendor: return "vendor (Go/PHP)"
        case .dartTool: return ".dart_tool (Dart)"
        case .pubCache: return ".pub-cache (Dart/Flutter)"
        case .dotCache: return ".cache (缓存)"
        }
    }

    public static let directoryNames: Set<String> = Set(allCases.map(\.rawValue))
}
