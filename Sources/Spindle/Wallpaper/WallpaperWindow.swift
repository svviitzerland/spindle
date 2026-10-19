import AppKit
import SceneKit

/// A full-screen window that lives on the desktop, under your icons.
///
/// The trick is the window level: one below `kCGDesktopIconWindowLevel` puts
/// the scene behind the icons but in front of the system wallpaper, which is
/// exactly where a live wallpaper belongs. Everything else here is about
/// staying out of the way — no mouse events, no Mission Control, no shadow,
/// and present on every Space.
final class WallpaperWindow: NSWindow {

    private let sceneView = SCNView()
    private let trackInfo = TrackInfoView()
    private var bottomInset: NSLayoutConstraint?
    private var leadingInset: NSLayoutConstraint?

    init(screen: NSScreen, scene: SCNScene, pointOfView: SCNNode, frameRateLimit: Int) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        isMovable = false
        canHide = false
        displaysWhenScreenProfileChanges = true

        sceneView.frame = NSRect(origin: .zero, size: screen.frame.size)
        sceneView.autoresizingMask = [.width, .height]
        sceneView.scene = scene
        sceneView.pointOfView = pointOfView
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling2X
        sceneView.preferredFramesPerSecond = frameRateLimit
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
        sceneView.allowsCameraControl = false

        let container = NSView(frame: sceneView.frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(sceneView)
        container.addSubview(trackInfo)
        trackInfo.translatesAutoresizingMaskIntoConstraints = false
        // Inset by whatever the Dock and menu bar are occupying, so the caption
        // is never printed underneath the Dock.
        let gutter: CGFloat = 40
        bottomInset = trackInfo.bottomAnchor.constraint(
            equalTo: container.bottomAnchor,
            constant: -(screen.visibleFrame.minY - screen.frame.minY) - gutter)
        leadingInset = trackInfo.leadingAnchor.constraint(
            equalTo: container.leadingAnchor,
            constant: (screen.visibleFrame.minX - screen.frame.minX) + gutter)
        NSLayoutConstraint.activate([leadingInset, bottomInset].compactMap { $0 })
        contentView = container

        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(for screen: NSScreen) {
        setFrame(screen.frame, display: true)
        // The Dock can move or hide while we are running.
        let gutter: CGFloat = 40
        bottomInset?.constant = -(screen.visibleFrame.minY - screen.frame.minY) - gutter
        leadingInset?.constant = (screen.visibleFrame.minX - screen.frame.minX) + gutter
    }

    func setFrameRateLimit(_ fps: Int) {
        sceneView.preferredFramesPerSecond = fps
    }

    func setTrackInfo(_ playing: NowPlaying?, visible: Bool) {
        trackInfo.isHidden = !visible || playing == nil
        trackInfo.apply(playing)
    }
}

/// The small caption in the corner. Deliberately plain: it should read as part
/// of the desktop, not as a window someone forgot to close.
private final class TrackInfoView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        sourceLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        artistLabel.font = .systemFont(ofSize: 14, weight: .regular)
        artistLabel.textColor = NSColor.white.withAlphaComponent(0.62)

        let stack = NSStackView(views: [sourceLabel, titleLabel, artistLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // A soft shadow keeps the text readable over a bright scene.
        for label in [titleLabel, artistLabel, sourceLabel] {
            label.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
                shadow.shadowBlurRadius = 8
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                return shadow
            }()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ playing: NowPlaying?) {
        guard let playing else { return }
        titleLabel.stringValue = playing.title
        artistLabel.stringValue = playing.artist
        sourceLabel.stringValue = (playing.isPlaying ? "NOW PLAYING · " : "PAUSED · ")
            + playing.source.displayName.uppercased()
    }
}
