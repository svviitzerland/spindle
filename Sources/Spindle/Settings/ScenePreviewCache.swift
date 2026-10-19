import AppKit
import Combine

/// Thumbnails for the scene picker.
///
/// They are rendered by the same renderer that draws the wallpaper, rather
/// than shipped as images — so a preview can never drift out of date when
/// someone edits a preset, and the repository stays free of binary assets.
@MainActor
final class ScenePreviewCache: ObservableObject {

    @Published private(set) var previews: [String: NSImage] = [:]
    @Published private(set) var isRendering = false

    private var hasStarted = false

    /// Render every preset once. Safe to call repeatedly.
    func loadIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        isRendering = true

        Task.detached(priority: .userInitiated) {
            for preset in ScenePreset.all {
                // 16:9, matching both the card and the framing each preset's
                // camera was composed for. A taller crop widens the vertical
                // field and fills the thumbnail with wall.
                guard let image = try? StillRenderer.render(
                    preset: preset,
                    size: CGSize(width: 640, height: 360),
                    seed: "preview",
                    progress: 0.3,
                    atTime: 2.0
                ) else { continue }

                await MainActor.run { self.previews[preset.id] = image }
            }
            await MainActor.run { self.isRendering = false }
        }
    }
}
