import ServiceManagement
import SwiftUI

/// 설정 (⌘,). 네이티브 Settings 씬 — 일반 / Command Palette / 보안 / 저장소 / 정보.
/// 모든 항목은 실제 동작한다 (더미 스위치 없음).
struct SettingsView: View {
    @AppStorage("clipboardClearDelay") private var clearDelay: Double = 30
    @AppStorage("vaultAutoLock") private var vaultAutoLock = false
    @AppStorage("vaultBiometric") private var vaultBiometric = true

    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var hotkeyRegistered = false

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    .help("macOS 로그인 시 CapsuleStash를 자동으로 실행합니다")
            }

            Section("Command Palette") {
                HStack {
                    Text("글로벌 단축키")
                    Spacer()
                    Text("⌘⇧Space")
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.tagBackground, in: Capsule())
                }
                HStack {
                    Text(hotkeyRegistered ? "등록됨 — 다른 앱에서도 호출됩니다" : "등록 실패 — 앱 안에서만 동작합니다")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("다시 등록") {
                        NotificationCenter.default.post(name: .capsuleReregisterHotKey, object: nil)
                        refreshHotkeyStatus()
                    }
                }
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
            }

            Section("정보") {
                HStack {
                    Text("버전")
                    Spacer()
                    Text(bundleVersion).foregroundStyle(Theme.muted)
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
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build))"
    }
}

extension Notification.Name {
    static let capsuleReregisterHotKey = Notification.Name("CapsuleStash.reregisterHotKey")
}
