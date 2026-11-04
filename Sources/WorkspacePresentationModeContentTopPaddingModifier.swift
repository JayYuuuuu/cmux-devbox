import SwiftUI

struct WorkspacePresentationModeContentTopPaddingModifier: ViewModifier {
    let isFullScreen: Bool
    let titlebarPadding: CGFloat
    let hostingSafeAreaTop: CGFloat

    @AppStorage(WorkspacePresentationModeSettings.modeKey)
    private var workspacePresentationMode = WorkspacePresentationModeSettings.defaultMode.rawValue

    private var isMinimalMode: Bool {
        WorkspacePresentationModeSettings.mode(for: workspacePresentationMode) == .minimal
    }

    @AppStorage(DevBoxCardChrome.enabledKey) private var devBoxCardChromeSetting = true

    /// DevBox card layout in minimal mode: the whole card (not the workspace
    /// inside it) rises into the titlebar band, so the card keeps its top
    /// gap, outline and tab bar instead of having them pushed off the window.
    private var cardOwnsTitlebarBand: Bool {
        isMinimalMode && !isFullScreen && DevBoxCardChrome.isEnabled(storedValue: devBoxCardChromeSetting)
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, cardOwnsTitlebarBand ? 0 : ContentView.effectiveTitlebarPadding(
                isMinimalMode: isMinimalMode,
                isFullScreen: isFullScreen,
                titlebarPadding: titlebarPadding,
                hostingSafeAreaTop: hostingSafeAreaTop
            ))
            .ignoresSafeArea(.container, edges: cardOwnsTitlebarBand ? .top : [])
    }
}
