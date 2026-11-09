import CmuxFoundation
import Observation
import SwiftUI

enum CommandPaletteRenderTrailingLabelStyle: Equatable {
    case shortcut
    case kind
}

struct CommandPaletteRenderTrailingLabel: Equatable {
    let text: String
    let style: CommandPaletteRenderTrailingLabelStyle
}

struct CommandPaletteRenderResultRow: Identifiable, Equatable {
    let id: String
    let title: String
    let matchedIndices: Set<Int>
    let trailingLabel: CommandPaletteRenderTrailingLabel?
}

struct CommandPaletteCommandListRenderState: Equatable {
    var resultsVersion: UInt64 = 0
    var emptyStateText: String = ""
    var listIdentity: String = "switcher"
    var rows: [CommandPaletteRenderResultRow] = []
    var selectedIndex: Int = 0
    var shouldShowEmptyState = false
    var scrollTargetID: String?
    var scrollTargetAnchor: UnitPoint?

    static let empty = CommandPaletteCommandListRenderState()
}

@MainActor
@Observable
final class CommandPaletteOverlayRenderModel {
    private(set) var commandList = CommandPaletteCommandListRenderState.empty
    @ObservationIgnored private var scheduledCommandListSequence: UInt64 = 0
    @ObservationIgnored private var appliedCommandListSequence: UInt64 = 0
    @ObservationIgnored private var appliedCommandListResultsVersion: UInt64 = 0

    deinit {}

    func scheduleCommandListUpdate(_ state: CommandPaletteCommandListRenderState) {
        scheduledCommandListSequence &+= 1
        let sequence = scheduledCommandListSequence

        Task { @MainActor in
            await Task.yield()
            guard sequence >= appliedCommandListSequence else { return }
            guard state.resultsVersion >= appliedCommandListResultsVersion else { return }
            appliedCommandListSequence = sequence
            appliedCommandListResultsVersion = max(appliedCommandListResultsVersion, state.resultsVersion)
            updateCommandList(state)
        }
    }

    private func updateCommandList(_ state: CommandPaletteCommandListRenderState) {
        guard commandList != state else { return }
        commandList = state
    }
}

struct CommandPaletteCommandListRenderView: View {
    let renderModel: CommandPaletteOverlayRenderModel
    let onRunResult: (String) -> Void

    var body: some View {
        CommandPaletteCommandListRowsView(
            state: renderModel.commandList,
            onRunResult: onRunResult
        )
    }
}

struct CommandPaletteCommandListRowsView: View {
    let state: CommandPaletteCommandListRenderState
    let onRunResult: (String) -> Void
    @State private var hoveredIndex: Int?

    private static let listMaxHeight: CGFloat = 450
    private static let rowHeight: CGFloat = 24
    private static let emptyStateHeight: CGFloat = 44

    var body: some View {
        let rowHeight = DevBoxPaletteChrome.isActive ? DevBoxPaletteChrome.rowHeight : Self.rowHeight
        // DevBox pills float with a small gap below the last row.
        let bottomInset: CGFloat = DevBoxPaletteChrome.isActive && !state.rows.isEmpty ? 6 : 0
        let contentHeight = state.rows.isEmpty
            ? Self.emptyStateHeight
            : CGFloat(state.rows.count) * rowHeight + bottomInset
        let listHeight = min(Self.listMaxHeight, contentHeight)

        ScrollView {
            LazyVStack(spacing: 0) {
                if state.rows.isEmpty {
                    if state.shouldShowEmptyState {
                        Text(state.emptyStateText)
                            .cmuxFont(size: 13, weight: .regular)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.emptyStateHeight)
                    }
                } else {
                    ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                        let isSelected = index == state.selectedIndex
                        let isHovered = hoveredIndex == index
                        let pills = DevBoxPaletteChrome.isActive
                        let rowBackground: Color = isSelected
                            ? (pills ? cmuxAccentColor() : cmuxAccentColor().opacity(0.12))
                            : (isHovered ? (pills ? DevBoxPaletteChrome.hoverFill : Color.primary.opacity(0.08)) : .clear)

                        Button {
                            onRunResult(row.id)
                        } label: {
                            ContentView.commandPaletteRenderResultLabelContent(
                                title: row.title,
                                matchedIndices: row.matchedIndices,
                                trailingLabel: row.trailingLabel,
                                onAccent: pills && isSelected
                            )
                            .padding(.horizontal, pills ? 10 : 9)
                            .padding(.vertical, pills ? 0 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: pills ? DevBoxPaletteChrome.rowHeight : nil)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: pills ? DevBoxPaletteChrome.rowCornerRadius : 0,
                                    style: .continuous
                                )
                                .fill(rowBackground)
                            )
                            .padding(.horizontal, pills ? DevBoxPaletteChrome.rowOuterInset : 0)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("CommandPaletteResultRow.\(index)")
                        .accessibilityValue(row.id)
                        .onHover { hovering in
                            if hovering {
                                hoveredIndex = index
                            } else if hoveredIndex == index {
                                hoveredIndex = nil
                            }
                        }
                    }
                }
            }
            .padding(.bottom, bottomInset)
            .scrollTargetLayout()
        }
        .id(state.listIdentity)
        .frame(height: listHeight)
        .scrollPosition(
            id: Binding(
                get: { state.scrollTargetID },
                // Ignore passive readback so manual scrolling doesn't mutate selection-follow state.
                set: { _ in }
            ),
            anchor: state.scrollTargetAnchor
        )
        .onChange(of: state.rows.count) { _, count in
            if let hoveredIndex, hoveredIndex >= count {
                self.hoveredIndex = nil
            }
        }
    }
}

/// Command palette panel: upstream's flat window-colored card, or in the
/// DevBox edition a rounder card in the terminal theme's colors with a lit
/// rim and a soft, deeper shadow.
struct CommandPalettePanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        if DevBoxPaletteChrome.isActive {
            let shape = RoundedRectangle(cornerRadius: DevBoxPaletteChrome.cornerRadius, style: .continuous)
            content
                .clipShape(shape)
                .background(shape.fill(DevBoxPaletteChrome.panelFill))
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: DevBoxPaletteChrome.rimColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: DevBoxPaletteChrome.shadowColor, radius: 24, x: 0, y: 12)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
        }
    }
}

/// Search row: upstream's plain padded field, or in the DevBox edition a
/// recessed rounded well (with the magnifier glyph placed by the caller).
struct CommandPaletteSearchFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        if DevBoxPaletteChrome.isActive {
            content
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DevBoxPaletteChrome.searchFieldFill)
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
        } else {
            content
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
    }
}
