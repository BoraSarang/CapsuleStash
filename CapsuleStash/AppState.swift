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

    func notify(_ message: String) {        toast = ToastMessage(text: message)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func notifyCopy(_ label: String, isSecret: Bool = false) {
        notify(isSecret ? "\(label) 복사됨 — \(ClipboardService.clearDelayDescription)" : "\(label) 복사됨")
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