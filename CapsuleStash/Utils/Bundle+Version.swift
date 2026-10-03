import Foundation

/// 번들 버전 표기 공유 (DebugPanel·설정).
extension Bundle {
    var capsuleVersionString: String {
        let info = infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build))"
    }
}
