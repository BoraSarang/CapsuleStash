import AppKit
import ServiceManagement
import SwiftUI

/// 설정 (⌘,). 네이티브 Settings 씬 — 일반 / Command Palette / 보안 / 저장소 / 정보.
/// 모든 항목은 실제 동작한다 (더미 스위치 없음).
struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("clipboardClearDelay") private var clearDelay: Double = 30
    @AppStorage("vaultAutoLock") private var vaultAutoLock = false
    @AppStorage("vaultBiometric") private var vaultBiometric = true
    @AppStorage("vaultLockOnQuit") private var vaultLockOnQuit = true
    @AppStorage("showDockIcon") private var showDockIcon = false
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("appearanceMode") private var appearanceMode = Theme.AppearanceMode.system.rawValue
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true
    @State private var lastBackupText: String = ""

    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var hotkeyRegistered = false
    @AppStorage("hotkeyKeyCode") private var hotkeyCode = 47
    @AppStorage("hotkeyModifiers") private var hotkeyMods = Int(NSEvent.ModifierFlags.command.rawValue)
    @StateObject private var hotkeyRecorder = HotkeyRecorder()

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    .help("macOS 로그인 시 Capsule Stash를 자동으로 실행합니다")
                Toggle("Dock에 아이콘 표시", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, _ in CapsuleStashApp.applyDockVisibility() }
                    .help("끄면 메뉴바에만 상주합니다. 즉시 적용됩니다")
            }

            Section("Command Palette") {
                HStack {
                    Text("글로벌 단축키")
                    Spacer()
                    Text(currentHotkey.display)
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.tagBackground, in: Capsule())
                }
                HStack {
                    Text(hotkeyRegistered
                        ? LocalizedStringKey("등록됨 — 다른 앱에서도 호출됩니다")
                        : LocalizedStringKey("등록 실패 — 앱 안에서만 동작합니다"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button(hotkeyRecorder.isRecording
                        ? LocalizedStringKey("취소")
                        : LocalizedStringKey("단축키 변경")) {
                        hotkeyRecorder.isRecording ? hotkeyRecorder.stop() : startHotkeyRecording()
                    }
                    .help("원하는 키를 직접 누르면 저장됩니다")
                    Button("다시 등록") {
                        NotificationCenter.default.post(name: .capsuleReregisterHotKey, object: nil)
                        refreshHotkeyStatus()
                    }
                }
                if hotkeyRecorder.isRecording {
                    Text("바꿀 단축키를 누르세요… (esc 취소, ⌘·⌃ 중 하나 필요)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
            }

            Section("모양") {
                Picker("테마", selection: $appearanceMode) {
                    Text("시스템 설정 따름").tag(Theme.AppearanceMode.system.rawValue)
                    Text("라이트").tag(Theme.AppearanceMode.light.rawValue)
                    Text("다크").tag(Theme.AppearanceMode.dark.rawValue)
                }
                .pickerStyle(.radioGroup)
                .help("앱 전체 밝기를 바꾼다. 즉시 적용된다")
                .onChange(of: appearanceMode) { _, _ in Theme.applyAppearance() }
            }

            Section("언어") {
                Picker("언어", selection: $appLanguage) {
                    Text("시스템 설정 따름").tag("system")
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .pickerStyle(.radioGroup)
                .help("앱 화면은 즉시 바뀌고, 메뉴·창 제목은 재시작 후 적용됩니다")
                .onChange(of: appLanguage) { _, _ in AppLanguage.applyBundleLanguage() }
            }

            Section("보안") {
                Picker("비밀값 클립보드 자동 삭제", selection: $clearDelay) {
                    Text("안 함").tag(0.0)
                    Text("10초").tag(10.0)
                    Text("30초").tag(30.0)
                    Text("1분").tag(60.0)
                }
                .pickerStyle(.radioGroup)
                .help("아이디·패스워드 복사 후 지정 시간이 지나면 클립보드를 비웁니다")
                Toggle("백그라운드 전환 시 Vault 잠금", isOn: $vaultAutoLock)
                    .help("다른 앱으로 전환되면 Vault를 자동으로 잠급니다")
                Toggle("종료 시 Vault 잠금", isOn: $vaultLockOnQuit)
                    .help("앱을 끝낼 때 Vault를 잠그고 클립보드의 비밀값을 지웁니다")
                Toggle("생체 인증으로 Vault 해제", isOn: $vaultBiometric)
                    .help("Touch ID·Face ID를 지원하면 해제 시 인증합니다. 미지원 기기는 바로 해제됩니다")
            }

            Section("저장소") {
                HStack {
                    Text(PersistenceStore.fileURL.path)
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Finder에서 보기") {
                        NSWorkspace.shared.activateFileViewerSelecting([PersistenceStore.fileURL])
                    }
                }
                Text("홈페이지·아이디는 로컬 파일에, 시크릿 2종은 Keychain에 암호화 보관됩니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                HStack {
                    Button("전체 내보내기 (JSON)") { exportAll() }
                    Button("가져오기 (JSON)") { importJSON() }
                    Spacer()
                }
                .padding(.top, 2)
                Divider()
                Toggle("자동 백업", isOn: $autoBackupEnabled)
                    .help("앱 실행 시 하루 1회 스냅샷을 저장하고 7세대만 보관합니다")
                HStack {
                    Text("마지막 백업")
                    Spacer()
                    Text(lastBackupText).foregroundStyle(Theme.muted)
                }
                HStack {
                    Button("지금 백업") { manualBackup() }
                    Button("백업 복원") { restoreBackup() }
                    Spacer()
                }
                .padding(.top, 2)
            }

            Section("정보") {
                HStack {
                    Text("버전")
                    Spacer()
                    Text(bundleVersion).foregroundStyle(Theme.muted)
                }
                HStack {
                    Text("업데이트")
                    Spacer()
                    Text(appState.updateStatusText).foregroundStyle(Theme.muted)
                }
                Picker("자동 확인", selection: $appState.updateFrequency) {
                    ForEach(UpdateFrequency.allCases) { frequency in
                        Text(LocalizedStringKey(frequency.labelKey)).tag(frequency)
                    }
                }
                .pickerStyle(.radioGroup)
                HStack {
                    Spacer()
                    Button("업데이트 확인") {
                        Task {
                            await appState.checkForUpdate(manual: true)
                            // 메인 창이 닫혀 있으면 시트가 안 뜨니 먼저 연다
                            if appState.updateSheetPresented {
                                openWindow(id: AppState.mainWindowID)
                            }
                        }
                    }
                    .disabled(appState.updateState == .checking)
                }
                HStack {
                    Text("번들 ID")
                    Spacer()
                    Text(Bundle.main.bundleIdentifier ?? "-")
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(12)
        .onAppear {
            refreshLaunchStatus()
            refreshHotkeyStatus()
            refreshBackupText()
        }
        .onDisappear {
            hotkeyRecorder.stop()
        }
        .alert("로그인 시 실행 설정 실패", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text((launchError ?? "") + "\n(\(ErrorCode.launchAtLogin))")
        }
    }

    // MARK: - 동작
    /// @AppStorage 값에서 조합을 읽는다 (저장 즉시 표시 갱신).
    private var currentHotkey: HotkeyCombo {
        HotkeyCombo(modifiers: NSEvent.ModifierFlags(rawValue: UInt(hotkeyMods)),
                    keyCode: UInt32(hotkeyCode))
    }

    private func startHotkeyRecording() {
        hotkeyRecorder.onCapture = { [weak hotkeyRecorder] keyCode, flags in
            HotkeyCombo(modifiers: flags, keyCode: keyCode).save()
            hotkeyRecorder?.stop()
            // @AppStorage가 같은 키를 보므로 표시·메뉴 단축키가 자동 갱신된다
            NotificationCenter.default.post(name: .capsuleReregisterHotKey, object: nil)
            refreshHotkeyStatusSoon()
            DebugLogger.feature("단축키 변경: \(HotkeyCombo.saved().display)")
        }
        hotkeyRecorder.onCancel = { [weak hotkeyRecorder] in
            hotkeyRecorder?.stop()
        }
        hotkeyRecorder.start()
    }

    /// 재등록 결과 반영을 기다렸다가 상태를 읽는다 (post 직후는 구값).
    private func refreshHotkeyStatusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.refreshHotkeyStatus()
        }
    }

    private func refreshLaunchStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func refreshHotkeyStatus() {
        hotkeyRegistered = GlobalHotKeyCenter.shared.isRegistered
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            DebugLogger.feature("로그인 시 실행: \(enabled ? "켬" : "끔")")
        } catch {
            launchAtLogin = !enabled
            launchError = error.localizedDescription
            DebugLogger.error(code: ErrorCode.launchAtLogin, "로그인 항목 등록 실패")
        }
    }

    private var bundleVersion: String {
        Bundle.main.capsuleVersionString
    }

    // MARK: - T-50 전체 내보내기·가져오기 (시크릿 제외는 전송 계층이 보장)

    private func exportAll() {
        guard let data = try? LibraryTransfer.exportJSON(workspaces: store.workspaces) else {
            appState.notify("내보내기 실패")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CapsuleStash-backup.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try data.write(to: dest, options: .atomic)
            DebugLogger.feature("전체 내보내기: \(dest.lastPathComponent)")
            appState.notify("내보냄")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "내보내기 실패")
            appState.notify("내보내기 실패")
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let workspaces = try LibraryTransfer.decodeJSON(data)
            let count = store.importWorkspaces(workspaces)
            appState.notify(L10n.format("Workspace %lld개 가져옴", count))
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "가져오기 실패")
            appState.notify("가져오기 실패")
        }
    }

    // MARK: - T-51 백업 (스냅샷이라 시크릿 제외는 전송 계층이 보장)

    private func refreshBackupText() {
        if let last = BackupStore.savedLastBackupAt() {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.effectiveLocale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lastBackupText = formatter.string(from: last)
        } else {
            lastBackupText = L10n.string("백업 없음")
        }
    }

    private func manualBackup() {
        do {
            try BackupStore.performBackup(workspaces: store.workspaces)
            refreshBackupText()
            appState.notify("백업됨")
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "수동 백업 실패")
            appState.notify("백업 실패")
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = BackupStore.directoryURL
        panel.message = L10n.string("복원할 백업 파일을 고르세요. 새 복사본으로 들어옵니다.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let workspaces = try LibraryTransfer.decodeJSON(data)
            let count = store.importWorkspaces(workspaces)
            appState.notify(L10n.format("Workspace %lld개 가져옴", count))
        } catch {
            DebugLogger.error(code: ErrorCode.storeSave, "백업 복원 실패")
            appState.notify("가져오기 실패")
        }
    }
}

extension Notification.Name {
    static let capsuleReregisterHotKey = Notification.Name("CapsuleStash.reregisterHotKey")
}

// MARK: - 단축키 기록기 (T-36)

/// "단축키 변경" 후 다음 키 입력을 가로채 조합으로 돌려준다.
/// esc는 취소, ⌘·⌃ 없는 조합과 표시 불가 키는 무시하고 계속 기다린다.
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    /// 유효 조합 포착 시 (keyCode, 수정자).
    var onCapture: ((UInt32, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            // 입력이 어딘가에 타이핑되지 않게 삼킨다
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        // esc(53) 취소
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let keyCode = UInt32(event.keyCode)
        guard HotkeyCombo.isRecordable(keyCode: keyCode, modifiers: flags) else { return }
        onCapture?(keyCode, flags)
    }
}
