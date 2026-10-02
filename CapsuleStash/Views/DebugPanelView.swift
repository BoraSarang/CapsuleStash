import SwiftUI

/// T-08 DebugPanel — ERROR 0 / PERF / CACHE / 로그 마스킹 검증용.
/// native 시스템 UI 규칙 준수 (custom 프로필과 무관).
struct DebugPanelView: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var logs = DebugLogStore.shared

    @State private var levelFilter: Set<String> = []

    private let levels = ["ERROR", "PERF", "CACHE", "INFO"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            stats
            Divider()
            logList
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 12) {
            Label("DebugPanel", systemImage: "ladybug")
                .font(.headline)
            Text(bundleVersion)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                ForEach(levels, id: \.self) { level in
                    let active = levelFilter.contains(level)
                    Button {
                        if active { levelFilter.remove(level) } else { levelFilter.insert(level) }
                    } label: {
                        Text(level)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(active ? color(for: level) : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(active ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("비우기") { logs.clear() }
            Button {
                let text = logs.entries
                    .map { "\($0.level)\t\($0.date.formatted(.iso8601))\t\($0.message)" }
                    .joined(separator: "\n")
                ClipboardService.copy(text, label: "DebugPanel 로그")
            } label: {
                Label("복사", systemImage: "doc.on.doc")
            }
            .disabled(logs.entries.isEmpty)
        }
        .padding(12)
    }

    private var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build)) • \(store.workspaces.count) WS"
    }

    // MARK: - 통계

    private var stats: some View {
        HStack(spacing: 0) {
            statItem("ERROR", "\(logs.errorCount)", .red)
            statItem("PERF", "\(logs.perfEntries.count)", .orange)
            statItem("CACHE", "\(logs.cacheEntries.count)", .teal)
            Divider().frame(height: 34)
            ForEach(store.stats, id: \.0) { item in
                statItem(item.0, item.1, .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func statItem(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 74)
    }

    private func color(for level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "PERF": return .orange
        case "CACHE": return .teal
        default: return .gray
        }
    }

    // MARK: - 로그

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filteredEntries.isEmpty {
                    Text("표시할 로그가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(filteredEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.level)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .frame(width: 46, alignment: .leading)
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 62, alignment: .leading)
                            Text(entry.message)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var filteredEntries: [DebugLogStore.Entry] {
        guard !levelFilter.isEmpty else { return logs.entries.reversed() }
        return logs.entries.reversed().filter { levelFilter.contains($0.level) }
    }
}