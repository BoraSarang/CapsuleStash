import SwiftUI

/// T-05 메뉴바 상주 시 노출되는 메뉴.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("빠른 검색…") { appState.showPalette() }
                .keyboardShortcut(" ", modifiers: [.command, .shift])

            Divider()

            Button("Capsule Stash 열기") { openMainWindow() }

            Menu("최근 사용") {
                if store.recents.isEmpty {
                    Text("최근 사용 없음")
                } else {
                    ForEach(store.recents) { entry in
                        Button(entry.title) { open(entry) }
                    }
                }
            }

            Menu("Project 추가") {
                if store.workspaces.isEmpty {
                    Text("Workspace 없음")
                } else {
                    ForEach(store.workspaces.prefix(8)) { ws in
                        Button("\(ws.name)에 새 Project") {
                            _ = store.createProject(title: "새 Project", in: ws.id)
                            appState.notify("Project 생성됨 — 사이드바에서 이름 변경 가능")
                        }
                    }
                }
            }

            Divider()

            Button(store.isVaultUnlocked ? "Vault 잠금" : "Vault 잠금 해제") { toggleVault() }

            Button("DebugPanel") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .capsuleOpenDebugPanel, object: nil)
            }

            Divider()

            Button("종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
        }
    }

    /// 메인 창만 연다 (팔레트 없이). "열기"·최근 항목용.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppState.mainWindowID)
    }

    private func open(_ entry: RecentEntry) {
        guard let located = store.allProjects.first(where: { $0.project.id == entry.id }) else { return }
        store.select(located.project)
        openMainWindow()
        DebugLogger.feature("메뉴바 최근 항목 이동: \(entry.title)")
    }

    private func toggleVault() {
        if store.isVaultUnlocked {
            store.lockVault()
            appState.notify("Vault 잠금")
        } else {
            store.requestVaultUnlock { _ in
                appState.notify(store.isVaultUnlocked ? "Vault 잠금 해제" : "Vault 잠금 해제 실패")
            }
        }
    }
}

extension Notification.Name {
    static let capsuleOpenDebugPanel = Notification.Name("CapsuleStash.openDebugPanel")
}
