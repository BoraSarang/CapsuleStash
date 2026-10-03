import AppKit
import SwiftUI

/// T-03/T-04 루트 화면: 좌 트리 + 우 Project 문서 상세.
/// 목업 `.app` 그리드 대응.
struct ContentView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .bottom) {
            // HStack + 커스텀 핸들: HSplitView는 좌측에 시스템 여백을 만들어
            // 사이드바가 창 끝에 붙지 않으므로 직접 구현한다.
            HStack(spacing: 0) {
                if appState.isSidebarVisible {
                    SidebarColumn()
                }
                detail
                    .frame(minWidth: 540, maxWidth: .infinity)
            }
            .frame(minWidth: 900, minHeight: 620)

            if let toast = appState.toast {
                ToastView(message: toast)
                    .padding(.bottom, 28)
            }
        }
        .background(Theme.paper)
        .overlay {
            if appState.isPalettePresented {
                CommandPaletteView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.16), value: appState.toast)
        .animation(.easeOut(duration: 0.14), value: appState.isPalettePresented)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { appState.isSidebarVisible.toggle() }
                } label: {
                    Label(
                        appState.isSidebarVisible ? LocalizedStringKey("사이드바 숨기기") : LocalizedStringKey("사이드바 보이기"),
                        systemImage: "sidebar.left"
                    )
                }
                .help("사이드바 숨기기/보이기 (⌥⌘S)")
            }
            ToolbarItem(placement: .principal) {
                ToolbarSearchField()
            }
            // 목업 `.newbtn`(잉크 필) 스타일. secondaryAction은 macOS에서
            // leading으로 붙어 검색창과 겹쳐 보이므로 primaryAction 그룹으로 묶는다.
            // 그룹 대신 단일 HStack — 시스템 그룹 셀 간격이 비대칭으로 보여서 직접 묶는다.
            // 두 버튼 모두 30×28 고정 프레임이라 글리프가 항상 중앙에 온다.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 0) {
                    addMenu
                    Button {
                        openWindow(id: AppState.debugWindowID)
                        DebugLogger.feature("DebugPanel 열기")
                    } label: {
                        Image(systemName: "ladybug")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("DebugPanel (⌘⇧D)")
                }
            }
        }
        .toolbarBackground(Theme.titlebar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear {
            DebugLogger.feature("ContentView 표시")
            Task { await appState.maybeAutoCheckForUpdate() }
            // T-51 기동 시 1일 1회 자동 백업 (조용히, 7세대 보관)
            let snapshot = store.workspaces
            Task.detached(priority: .utility) {
                BackupStore.maybeBackupIfDue(workspaces: snapshot)
            }
        }
        // T-47 새 버전 시트 (설정·메뉴바가 함께 띄운다)
        .sheet(isPresented: $appState.updateSheetPresented) {
            if let update = appState.availableUpdate {
                UpdateAvailableSheet(tag: update.tag, htmlURL: update.htmlURL, notes: update.notes)
            }
        }
        // T-17 종료 시 Vault 잠금 + 클립보드 비밀값 정리
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.lockVaultOnQuitIfNeeded()
        }
    }

    // MARK: - 타이틀바 새 블록 추가

    @State private var isAddingBlock = false

    /// Toolbar에는 Menu를 쓰지 않는다 — 숨긴 인디케이터 자리 때문에 셀이 비대칭으로 보인다.
    /// 무당벌레와 같은 일반 Button + 팝오버로 맞춘다.
    private var addMenu: some View {
        Button {
            isAddingBlock = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.selectedProject == nil)
        .help("새로 만들기 — 현재 Project에 블록 추가")
        .popover(isPresented: $isAddingBlock) {
            if let project = store.selectedProject {
                BlockTypePicker(projectId: project.id) { isAddingBlock = false }
            }
        }
    }

    // MARK: - 상세 영역

    @ViewBuilder
    private var detail: some View {
        if let project = store.selectedProject, let located = store.locate(project) {
            ProjectDetailView(
                project: project,
                workspaceName: located.workspace.name
            )
        } else {
            EmptyStateView(
                title: "Project를 선택하세요",
                systemImage: "capsule",
                message: "왼쪽에서 Workspace → Project를 골라보세요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
        }
    }
}

// MARK: - 사이드바 열 (너비 + 조절 핸들)
//
// 드래그 중 너비는 이 열의 로컬 상태로만 갱신한다. AppState(@Published)에 바로 쓰면
// 틱마다 앱 전체가 리렌더되어 디테일 이미지 재로드까지 일어나 심하게 떨린다.
// 손을 놓을 때(onEnd) 한 번만 저장한다.
private struct SidebarColumn: View {
    @EnvironmentObject private var appState: AppState
    @State private var liveWidth: CGFloat?

    private var width: CGFloat { liveWidth ?? appState.sidebarWidth }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: width)
            ResizeHandle(
                startWidth: width,
                onChange: { liveWidth = $0 },
                onEnd: { appState.setSidebarWidth($0) },
                onToggle: {
                    withAnimation(.easeOut(duration: 0.18)) { appState.isSidebarVisible.toggle() }
                }
            )
        }
    }
}

// MARK: - 사이드바 조절 핸들
//
// HSplitView는 좌측에 시스템 여백을 만들어 사이드바가 창 끝에 붙지 않으므로,
// HStack + 커스텀 드래그 핸들로 구현한다. 호버 시 좌우 리사이즈 커서,
// 드래그로 140~340 조절, 더블클릭으로 숨기기/보이기.
private struct ResizeHandle: View {
    var startWidth: CGFloat
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void
    var onToggle: () -> Void

    @State private var dragBase: CGFloat?
    @State private var current: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 9)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(isHovering ? Theme.accent : Theme.line)
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragBase == nil { dragBase = startWidth }
                        guard let base = dragBase else { return }
                        let width = min(
                            AppState.sidebarMaxWidth,
                            max(AppState.sidebarMinWidth, base + value.translation.width)
                        )
                        current = width
                        onChange(width)
                    }
                    .onEnded { _ in
                        if let final = current { onEnd(final) }
                        dragBase = nil
                        current = nil
                    }
            )
            .onTapGesture(count: 2) { onToggle() }
            .help("드래그로 너비 조절 · 더블클릭으로 숨기기/보이기")
    }
}

// MARK: - 타이틀바 검색 버튼 (목업 `.searchbar`)
//
// Tahoe 툴바 principal 자리는 시스템이 이미 필 배경을 그려준다.
// 여기서 배경·테두리를 또 그리면 두 겹으로 보이므로 (구 가짜 필드와 동일 원인),
// 내용은 투명으로 두고 시스템 필만 살린다. 클릭하면 Command Palette를 연다.
private struct ToolbarSearchField: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("hotkeyKeyCode") private var hotkeyCode = 47
    @AppStorage("hotkeyModifiers") private var hotkeyMods = Int(NSEvent.ModifierFlags.command.rawValue)

    private var combo: HotkeyCombo {
        HotkeyCombo(modifiers: NSEvent.ModifierFlags(rawValue: UInt(hotkeyMods)),
                    keyCode: UInt32(hotkeyCode))
    }

    var body: some View {
        Button {
            appState.showPalette()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                Text("검색")
                    .font(.system(size: 13))
                Text(combo.display)
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 160, maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.format("클릭하거나 %@ 로 Command Palette 열기", combo.display))
    }
}