import SwiftUI

// MARK: - 목업(mockup-v0.1.html) 공통 컴포넌트

/// 블록 타입 배지 (`<span class="type …">`)
struct TypeBadge: View {
    let text: String
    let type: BlockType
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .kerning(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.badgeColor(for: type), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 목업 `.iconbtn` 버튼
struct CapsuleButton: View {
    enum Style {
        case plain      // 흰 배경 + 테두리
        case primary    // 잉크 배경 + 흰 글자
        case ghost      // 투명 배경, 사이드바용
    }

    let title: String
    var systemImage: String?
    var style: Style = .plain
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .plain, .ghost: return Theme.ink
        case .primary: return Theme.paper
        }
    }

    private var background: Color {
        switch style {
        case .plain: return Theme.card
        case .primary: return Theme.ink
        case .ghost: return .clear
        }
    }

    private var border: Color {
        switch style {
        case .plain: return Theme.line
        case .primary: return Theme.ink
        case .ghost: return Theme.sidebarLine
        }
    }
}

/// 아이콘 전용 액션 버튼. 텍스트 대신 hover 툴팁으로 의미를 전달한다.
/// 버튼 줄바꿈(두 줄 깨짐) 방지용 표준 — 카드 헤더·컬렉션 헤더·팔레트 행에 사용.
/// 다이얼로그 푸터(취소/저장/추가/확인)·메뉴 항목·칩/네비게이션 행은 텍스트 유지.
/// (목업 `.iconbtn`은 아이콘+텍스트이나 공간상 통일. docs/DESIGN.md §4)
struct CapsuleIconButton: View {
    let systemImage: String
    let tooltip: String
    var style: CapsuleButton.Style = .plain
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(tint ?? foreground)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private var foreground: Color {
        switch style {
        case .plain, .ghost: return Theme.ink
        case .primary: return Theme.paper
        }
    }

    private var background: Color {
        switch style {
        case .plain: return Theme.card
        case .primary: return Theme.ink
        case .ghost: return .clear
        }
    }

    private var border: Color {
        switch style {
        case .plain: return Theme.line
        case .primary: return Theme.ink
        case .ghost: return Theme.sidebarLine
        }
    }
}

/// 태그 칩
struct TagChip: View {
    let text: String

    var body: some View {
        Text("#\(text)")
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.tagBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// 사이드바 섹션 라벨 (`<h4>WORKSPACE</h4>`)
struct SidebarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(Theme.sidebarMuted)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Toast
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        Text(message.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.ink, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// 비어 있는 상태 표시 (네이티브 시스템 UI 규칙 준수)
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(Theme.serif(22))
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                Text("⌘").font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("⇧").font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("Space").font(.system(size: 11, design: .monospaced))
                Text("로 어디서든 검색").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.tagBackground, in: Capsule())
        }
        .padding(40)
    }
}