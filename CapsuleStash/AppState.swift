import AppKit
import SwiftUI

/// 창 전환 · Command Palette 표시 · 토스트 메시지를 관리하는 전역 상태.
@MainActor
final class AppState: ObservableObject {
    @Published var isPalettePresented: Bool = false
    @Published var toast: ToastMessage?
    @Published var blockCreation: BlockCreationRequest?
    /// T-43 팔레트에서 선택한 블록으로 이동 요청 (ProjectDetailView가 소비 후 nil로 비운다).
    @Published var pendingBlockScroll: UUID?

    /// 사이드바 표시 상태 (UserDefaults 유지)
    @Published var isSidebarVisible: Bool {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: Self.sidebarVisibleKey) }
    }
    private static let sidebarVisibleKey = "sidebarVisible"
    private static let sidebarWidthKey = "sidebarWidth"

    /// 사이드바 너비 (드래그 조절, UserDefaults 유지)
    @Published var sidebarWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: Self.sidebarWidthKey) }
    }

    static let sidebarMinWidth: CGFloat = 140
    static let sidebarMaxWidth: CGFloat = 340

    init() {
        self.isSidebarVisible = UserDefaults.standard.object(forKey: Self.sidebarVisibleKey) as? Bool ?? true
        let saved = UserDefaults.standard.object(forKey: Self.sidebarWidthKey) as? Double ?? 200
        self.sidebarWidth = min(Self.sidebarMaxWidth, max(Self.sidebarMinWidth, saved))
        self.updateFrequency = Self.savedUpdateFrequency()
    }

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = min(Self.sidebarMaxWidth, max(Self.sidebarMinWidth, width))
    }

    /// T-14 카드 드롭 선점 플래그. 카드 onDrop이 먼저 실행돼 이미지·파일 블록이
    /// 파일 소비를 선언하면, 상세 화면의 파일 드롭은 건너뛰고 텍스트·URL만 처리한다.
    var fileDropHandled = false

    /// 블록 추가 요청. 타입 선택 → 입력 시트 표시 → 저장 시 생성, 취소 시 미생성.
    func requestBlockCreation(type: BlockType, in projectId: UUID) {
        blockCreation = BlockCreationRequest(projectId: projectId, type: type)
        DebugLogger.feature("블록 추가 입력창: \(type.displayName)")
    }

    /// 메인 창 Scene id (CapsuleStashApp 에서 사용)
    static let mainWindowID = "main"
    static let debugWindowID = "debug"

    private var toastTask: Task<Void, Never>?

    func showPalette() {
        NSApp.activate(ignoringOtherApps: true)
        isPalettePresented = true
        DebugLogger.feature("Command Palette 열림")
    }

    func hidePalette() {
        isPalettePresented = false
    }

    /// Vault 잠금/해제 토글 (메뉴바·사이드바 공유).
    func toggleVault(_ store: DataStore) {
        if store.isVaultUnlocked {
            store.lockVault()
            notify("Vault 잠금")
        } else {
            store.requestVaultUnlock { [weak self] _ in
                self?.notify(store.isVaultUnlocked ? "Vault 잠금 해제" : "Vault 잠금 해제 실패")
            }
        }
    }

    /// 외부 링크를 기본 브라우저로 연다 (카드·본문 공유).
    func openExternal(_ url: URL) {
        DebugLogger.feature("외부 링크 열기: \(url.host() ?? url.absoluteString)")
        NSWorkspace.shared.open(url)
    }

    /// 토스트 표시. 리터럴은 앱 표시 언어로 푼다 (T-46, 재시작 불필요).
    /// 키가 없으면(사용자 문구 등) 그대로 둔다.
    func notify(_ message: String) {
        toast = ToastMessage(text: L10n.string(message))
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func notifyCopy(_ label: String, isSecret: Bool = false) {
        let base = L10n.format("%@ 복사됨", label)
        notify(isSecret ? "\(base) — \(ClipboardService.clearDelayDescription)" : base)
    }

    // MARK: - 업데이트 확인 (T-47)

    /// 확인 상태. 설정 행·메뉴바 하단·시트가 함께 본다.
    @Published var updateState: UpdateState = .idle
    /// 새 버전 시트 (ContentView에 산다).
    @Published var updateSheetPresented = false
    @Published var updateFrequency: UpdateFrequency {
        didSet { UserDefaults.standard.set(updateFrequency.rawValue, forKey: Self.updateFrequencyKey) }
    }

    private static let updateFrequencyKey = "updateFrequency"
    private static let updateCheckedAtKey = "updateCheckedAt"
    private let launchDate = Date()

    /// 저장된 주기 (기본 매주). 테스트가 실설정을 오염시키지 않게 저장·복원한다.
    nonisolated static func savedUpdateFrequency() -> UpdateFrequency {
        UpdateFrequency(rawValue: UserDefaults.standard.string(forKey: updateFrequencyKey) ?? "") ?? .weekly
    }

    nonisolated private static func savedUpdateCheckedAt() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: updateCheckedAtKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    /// 주기에 따라 필요하면 조용히 확인한다. 앱 실행 시 1회.
    /// 자동 확인은 시트를 띄우지 않는다 (메뉴바 표시만 바뀐다).
    func maybeAutoCheckForUpdate() async {
        let lastChecked = Self.savedUpdateCheckedAt()
        guard ReleaseChecker.isDue(frequency: updateFrequency, lastChecked: lastChecked,
                                   now: Date(), launchDate: launchDate) else { return }
        await checkForUpdate()
    }

    /// 설정의 확인 버튼용. 새 버전이면 시트를 바로 띄운다.
    func checkForUpdate(manual: Bool = false) async {
        guard updateState != .checking else { return }
        updateState = .checking
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.updateCheckedAtKey)
        do {
            let release = try await ReleaseChecker.fetchLatest()
            if ReleaseChecker.isNewer(tag: release.tagName, than: Bundle.main.capsuleVersionString) {
                updateState = .updateAvailable(tag: release.tagName, htmlURL: release.htmlURL,
                                               notes: release.body ?? "")
                if manual { updateSheetPresented = true }
            } else {
                updateState = .upToDate
            }
        } catch ReleaseCheckError.noPublishedRelease {
            updateState = .unavailable("게시된 릴리스가 없습니다")
        } catch {
            updateState = .unavailable("업데이트 확인 실패")
        }
    }

    /// 새 버전이 있으면 (태그·페이지·노트).
    var availableUpdate: (tag: String, htmlURL: String, notes: String)? {
        if case .updateAvailable(let tag, let htmlURL, let notes) = updateState {
            return (tag, htmlURL, notes)
        }
        return nil
    }

    /// 설정 행 표시문. 키는 카탈로그에 있다.
    var updateStatusText: String {
        switch updateState {
        case .idle:
            return L10n.string("아직 확인하지 않음")
        case .checking:
            return L10n.string("확인 중…")
        case .upToDate:
            return L10n.string("최신 버전입니다")
        case .updateAvailable(let tag, _, _):
            return L10n.format("새 버전 %@ 사용 가능", tag)
        case .unavailable(let message):
            return L10n.string(message)
        }
    }
}

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

/// 블록 추가 요청 (생성 우선 플로우). 시트는 저장될 때만 블록을 만든다.
struct BlockCreationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectId: UUID
    let type: BlockType

    static func == (lhs: BlockCreationRequest, rhs: BlockCreationRequest) -> Bool {
        lhs.id == rhs.id
    }
}