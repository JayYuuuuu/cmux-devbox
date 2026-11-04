import SwiftUI

struct WorkspaceContentMinimalModeSafeAreaModifier: ViewModifier {
    let isFullScreen: Bool

    @AppStorage(WorkspacePresentationModeSettings.modeKey)
    private var workspacePresentationMode = WorkspacePresentationModeSettings.defaultMode.rawValue

    private var isMinimalMode: Bool {
        WorkspacePresentationModeSettings.mode(for: workspacePresentationMode) == .minimal
    }

    @AppStorage(DevBoxCardChrome.enabledKey) private var devBoxCardChromeSetting = true

    func body(content: Content) -> some View {
        // With the DevBox card the card itself rises into the titlebar band
        // (WorkspacePresentationModeContentTopPaddingModifier); the workspace
        // inside must stay within the card.
        let insideCard = DevBoxCardChrome.isEnabled(storedValue: devBoxCardChromeSetting)
        content.ignoresSafeArea(.container, edges: (isMinimalMode && !isFullScreen && !insideCard) ? .top : [])
    }
}
