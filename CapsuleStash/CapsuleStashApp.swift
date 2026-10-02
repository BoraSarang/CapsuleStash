import AppKit
import Combine
import SwiftUI

@main
struct CapsuleStashApp: App {
    @StateObject private var store: DataStore
    @StateObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var cancellables = Set<AnyCancellable>()
    /// 설정(⌘,)의 표시 언어. 바뀌면 전 씬 로케일이 즉시 바뀐다.
    @AppStorage("appLanguage") private var appLanguage = "system"

    init() {
        // 설정(⌘,)의 모양 선택을 가장 먼저 적용한다 (기본 시스템 추적).
        Theme.applyAppearance()
        // Dock 표시 여부 (기본 숨김). 설정에서 바꾸면 즉시 적용된다.
        Self.applyDockVisibility()
        _store = StateObject(wrappedValue: DataStore())
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        // appLanguage를 읽어 설정 변경 시 씬을 다시 그린다 (값은 effectiveLocale이 계산)
        let _ = appLanguage
        // 메인 창
        Window("Capsule Stash", id: AppState.mainWindowID) {
            ContentView()
                .environmentObject(store)
                .environmentObject(appState)
                .environment(\.locale, AppLanguage.effectiveLocale)
                .onAppear {
                    registerGlobalHotKey()
                    observeMenuBarRequests()
                    observeHotkeyReregister()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    // 설정(⌘,)에서 켠 경우: 백그라운드 전환 시 Vault 자동 잠금
                    guard UserDefaults.standard.bool(forKey: "vaultAutoLock"),
                          store.isVaultUnlocked else { return }
                    store.lockVault()
                    DebugLogger.feature("백그라운드 전환 — Vault 자동 잠금")
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { commands }

        // T-05 메뉴바 상주 — KnowledgeVault-macOS26 템플릿 아이콘 (라이트/다크 자동 틴트)
        MenuBarExtra("Capsule Stash", image: "MenuBar") {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(appState)
                .environment(\.locale, AppLanguage.effectiveLocale)
        }
        .menuBarExtraStyle(.menu)

        // T-08 DebugPanel (⌘⇧D)
        Window("DebugPanel", id: AppState.debugWindowID) {
            DebugPanelView()
                .environmentObject(store)
                .environmentObject(appState)
                .environment(\.locale, AppLanguage.effectiveLocale)
        }
        .defaultSize(width: 860, height: 560)
        .windowResizability(.contentMinSize)

        // 설정 (⌘,) — 네이티브 Settings 씬
        Settings {
            SettingsView()
                .environment(\.locale, AppLanguage.effectiveLocale)
        }
    }

    /// Dock 아이콘 표시 여부 (설정 키 `showDockIcon`, 기본 숨김).
    /// 켜면 `.regular`, 끄면 `.accessory` — 즉시 적용된다.
    static func applyDockVisibility() {
        let show = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? false
        NSApplication.shared.setActivationPolicy(show ? .regular : .accessory)
        DebugLogger.feature("Dock 아이콘: \(show ? "표시" : "숨김")")
    }

    // MARK: - 글로벌 단축키

    private func registerGlobalHotKey() {
        let ok = GlobalHotKeyCenter.shared.register { [weak appState] in
            MainActor.assumeIsolated {
                guard let appState else { return }
                if appState.isPalettePresented {
                    appState.hidePalette()
                } else {
                    appState.showPalette()
                }
            }
        }
        if ok {
            DebugLogger.feature("T-05 글로벌 단축키 ⌘⇧Space 활성화")
        } else {
            DebugLogger.error(code: ErrorCode.hotkeyRegister, "핫키 등록 실패 — 앱 내부 단축키만 사용 가능")
        }
    }

    private func observeMenuBarRequests() {
        NotificationCenter.default.publisher(for: .capsuleOpenDebugPanel)
            .sink { _ in
                MainActor.assumeIsolated { openWindow(id: AppState.debugWindowID) }
            }
            .store(in: &cancellables)
    }

    /// 설정(⌘,)의 "다시 등록" 요청을 받아 글로벌 단축키를 재등록한다.
    private func observeHotkeyReregister() {
        NotificationCenter.default.publisher(for: .capsuleReregisterHotKey)
            .sink { _ in
                MainActor.assumeIsolated { self.registerGlobalHotKey() }
            }
            .store(in: &cancellables)
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Capsule Stash"
        alert.informativeText = """
        Personal Knowledge Workspace for Mac
        텍스트·코드·웹 페이지·이미지·계정 정보를 Project 문서로 묶고,
        메뉴바와 ⌘⇧Space 로 언제든 검색하고 복사합니다.
        """
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    // MARK: - 메뉴

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("새로 만들기") {
                if store.workspaces.isEmpty {
                    Text("Workspace 없음")
                } else {
                    ForEach(store.workspaces.prefix(8)) { ws in
                        Button("\(ws.name)에 새 Project") {
                            _ = store.createProject(title: "새 Project", in: ws.id)
                        }
                    }
                }
            }
        }

        CommandGroup(after: .newItem) {
            Button("빠른 검색…") { appState.showPalette() }
                .keyboardShortcut(" ", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("DebugPanel") { openWindow(id: AppState.debugWindowID) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(appState.isSidebarVisible ? "사이드바 숨기기" : "사이드바 보이기") {
                withAnimation(.easeOut(duration: 0.18)) { appState.isSidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Button("Capsule Stash 정보") { showAbout() }
        }
    }
}