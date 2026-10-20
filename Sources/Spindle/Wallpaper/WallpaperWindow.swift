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
    private let lyricsView = LyricsView()
    private var lyricsConstraints: [NSLayoutConstraint] = []
    private var lyricsPlacement = TextPlacement(x: 0.055, y: 0.115, alignment: .leading)
    /// Holds the last rendered frame while the scene is paused, so a still
    /// wallpaper costs exactly what a desktop picture costs.
    private let heldFrame = NSImageView()
    /// Kept so the scene can be detached from the view while suspended and
    /// put back when it is needed again.
    private let heldScene: SCNScene
    private let heldPointOfView: SCNNode
    private var mode: RenderMode = .live(fps: 30)
    /// Raised when macOS covers or reveals the window.
    var onVisibilityChange: ((Bool) -> Void)?

    private var bottomInset: NSLayoutConstraint?
    private var leadingInset: NSLayoutConstraint?

    init(screen: NSScreen, scene: SCNScene, pointOfView: SCNNode, frameRateLimit: Int) {
        heldScene = scene
        heldPointOfView = pointOfView
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

        heldFrame.frame = sceneView.frame
        heldFrame.autoresizingMask = [.width, .height]
        heldFrame.imageScaling = .scaleAxesIndependently
        heldFrame.isHidden = true

        let container = NSView(frame: sceneView.frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(sceneView)
        container.addSubview(heldFrame)
        container.addSubview(trackInfo)
        container.addSubview(lyricsView)
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
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
        applyLyricsPlacement(in: screen)

        setFrame(screen.frame, display: true)

        // Stop drawing a room nobody can see. The desktop spends most of its
        // life completely covered by other windows, and rendering a 3-D scene
        // behind them is the single largest thing Spindle costs.
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func occlusionChanged() {
        onVisibilityChange?(occlusionState.contains(.visible))
    }

    /// Put the renderer to sleep properly.
    ///
    /// `isPlaying = false` only stops the scene's animation clock. The view
    /// keeps its display link running and goes on drawing the same frame
    /// sixty times a second, which a profile shows plainly: the SceneKit
    /// render queue stays busy and the Metal command queues with it. Hiding
    /// the view and detaching the scene is what actually stops the work.
    private func suspendRenderer() {
        guard sceneView.scene != nil else { return }
        sceneView.isPlaying = false
        sceneView.rendersContinuously = false
        sceneView.isHidden = true
        sceneView.scene = nil
    }

    private func resumeRenderer(fps: Int) {
        if sceneView.scene == nil {
            sceneView.scene = heldScene
            sceneView.pointOfView = heldPointOfView
        }
        sceneView.isHidden = false
        sceneView.preferredFramesPerSecond = fps
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
    }

    /// Take a fresh picture of the scene while paused.
    ///
    /// Needed whenever the room changes underneath a held frame: switching
    /// scene or pressing rebuilds the deck, and the picture on screen is of
    /// the old one.
    func redrawHeldFrame() {
        guard !heldFrame.isHidden else { return }
        let suspended = sceneView.scene == nil
        if suspended { resumeRenderer(fps: 30) }
        heldFrame.image = sceneView.snapshot()
        if suspended { suspendRenderer() }
    }

    /// Switch between drawing the scene and holding a picture of it.
    ///
    /// Going still takes one snapshot and then stops the renderer entirely.
    /// That single frame is the whole saving: an `NSImageView` showing a
    /// bitmap asks nothing of the GPU between now and whenever the music
    /// starts again.
    func apply(_ newMode: RenderMode) {
        guard newMode != mode else { return }
        let wasLive = mode.isLive
        mode = newMode

        switch newMode {
        case .live(let fps):
            resumeRenderer(fps: fps)
            heldFrame.isHidden = true
            heldFrame.image = nil

        case .still:
            // Only worth snapshotting if something has been moving since the
            // last one; otherwise the frame already on screen is current.
            if wasLive || heldFrame.image == nil {
                heldFrame.image = sceneView.snapshot()
            }
            heldFrame.isHidden = false
            suspendRenderer()

        case .off:
            // Nothing is visible, so do not spend a frame producing a
            // picture nobody will see. Keep whatever is already held.
            suspendRenderer()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(for screen: NSScreen) {
        setFrame(screen.frame, display: true)
        // The Dock can move or hide while we are running.
        let gutter: CGFloat = 40
        bottomInset?.constant = -(screen.visibleFrame.minY - screen.frame.minY) - gutter
        leadingInset?.constant = (screen.visibleFrame.minX - screen.frame.minX) + gutter
        applyLyricsPlacement(in: screen)
    }

    func setFrameRateLimit(_ fps: Int) {
        sceneView.preferredFramesPerSecond = fps
    }

    /// Lyrics sit wherever the current room has a clear wall, so the anchor
    /// moves with the scene rather than living in a fixed corner.
    func setLyricsPlacement(_ placement: TextPlacement, screen: NSScreen?) {
        guard placement != lyricsPlacement else { return }
        lyricsPlacement = placement
        applyLyricsPlacement(in: screen ?? self.screen ?? NSScreen.main!)
    }

    func setLyrics(_ lyrics: Lyrics?, elapsed: TimeInterval, duration: TimeInterval,
                   visible: Bool) {
        lyricsView.isHidden = !visible || lyrics == nil
        guard let lyrics else { return }
        lyricsView.apply(lyrics.window(elapsed: elapsed, duration: duration),
                         alignment: lyricsPlacement.alignment)
    }

    private func applyLyricsPlacement(in screen: NSScreen) {
        NSLayoutConstraint.deactivate(lyricsConstraints)
        guard let container = contentView else { return }

        let size = screen.frame.size
        let top = size.height * lyricsPlacement.y
        // Wide enough for a line of a song, narrow enough to stay off the deck.
        let width = min(size.width * 0.40, 560)

        var constraints: [NSLayoutConstraint] = [
            lyricsView.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            lyricsView.widthAnchor.constraint(equalToConstant: width),
        ]

        switch lyricsPlacement.alignment {
        case .leading:
            constraints.append(lyricsView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: size.width * lyricsPlacement.x))
        case .trailing:
            constraints.append(lyricsView.trailingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: size.width * lyricsPlacement.x))
        case .center:
            constraints.append(lyricsView.centerXAnchor.constraint(
                equalTo: container.leadingAnchor, constant: size.width * lyricsPlacement.x))
        }

        NSLayoutConstraint.activate(constraints)
        lyricsConstraints = constraints
    }

    func setTrackInfo(_ playing: NowPlaying?, visible: Bool) {
        trackInfo.isHidden = !visible || playing == nil
        trackInfo.apply(playing)
    }
}

/// Three lines of a song: the one being sung, with its neighbours faded.
///
/// Deliberately quiet. This is a wallpaper, and a wall of bright text over a
/// lit room would be the only thing anybody ever saw.
private final class LyricsView: NSView {
    private let previous = NSTextField(labelWithString: "")
    private let current = NSTextField(labelWithString: "")
    private let next = NSTextField(labelWithString: "")
    private let stack: NSStackView
    private var lastSignature: [String] = []
    private var lastAlignment: TextPlacement.Alignment?

    init() {
        stack = NSStackView(views: [previous, current, next])
        super.init(frame: .zero)
        wantsLayer = true

        previous.font = .systemFont(ofSize: 15, weight: .regular)
        previous.textColor = NSColor.white.withAlphaComponent(0.34)
        next.font = .systemFont(ofSize: 15, weight: .regular)
        next.textColor = NSColor.white.withAlphaComponent(0.34)
        current.font = .systemFont(ofSize: 23, weight: .medium)
        current.textColor = NSColor.white.withAlphaComponent(0.93)

        for label in [previous, current, next] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            label.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
                shadow.shadowBlurRadius = 10
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                return shadow
            }()
        }

        stack.orientation = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ window: (before: String?, current: String, after: String?),
               alignment: TextPlacement.Alignment) {
        // Called every second, but a line lasts several. Redrawing text that
        // has not changed is work for nothing.
        let signature = [window.before ?? "", window.current, window.after ?? ""]
        guard signature != lastSignature || alignment != lastAlignment else { return }
        lastSignature = signature
        lastAlignment = alignment

        previous.stringValue = window.before ?? ""
        current.stringValue = window.current
        next.stringValue = window.after ?? ""
        previous.isHidden = window.before == nil
        next.isHidden = window.after == nil

        let nsAlignment: NSTextAlignment
        switch alignment {
        case .leading: nsAlignment = .left
        case .center: nsAlignment = .center
        case .trailing: nsAlignment = .right
        }
        for label in [previous, current, next] { label.alignment = nsAlignment }
        stack.alignment = alignment == .trailing ? .trailing
            : (alignment == .center ? .centerX : .leading)
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
