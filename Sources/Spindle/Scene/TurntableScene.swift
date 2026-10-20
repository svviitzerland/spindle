import AppKit
import Foundation
import QuartzCore
import SceneKit

/// Stages the room: camera, light, desk, deck and dressing.
///
/// All of the object detail lives in `Deck` and `Props`; all of the surface
/// detail lives in `Materials`. What is left here is composition — which is
/// the part worth being able to read in one sitting.
final class TurntableScene {

    let scene = SCNScene()
    private(set) var preset: ScenePreset

    private let world = SCNNode()
    /// Carries the position and the look-at constraint.
    private let cameraRig = SCNNode()
    /// Child of the rig, so roll can be applied without fighting the constraint.
    private let cameraNode = SCNNode()
    private let lookTarget = SCNNode()

    private var deck: Deck
    private var pressing: Pressing
    private var artwork: NSImage
    private var isSpinning = false
    private var isArmLifted = true
    private var rpm: CGFloat = 33 + 1.0 / 3.0

    init(preset: ScenePreset = .daylight,
         seed: String = "spindle",
         pressing: Pressing = .black) {
        self.preset = preset
        self.pressing = pressing
        self.artwork = GenerativeCover.make(seed: seed).image
        self.deck = Deck(preset: preset, artwork: artwork, pressing: pressing)

        scene.rootNode.addChildNode(world)
        scene.rootNode.addChildNode(lookTarget)
        cameraRig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraRig)
        build()
    }

    var pointOfView: SCNNode { cameraNode }

    // MARK: Public controls

    func apply(_ newPreset: ScenePreset) {
        // Compared whole, not by id: following the clock moves the sun within
        // a room, so the same scene can genuinely need rebuilding.
        guard newPreset != preset else { return }
        preset = newPreset
        rebuild()
    }

    /// Change what the record is made of.
    func apply(_ newPressing: Pressing) {
        guard newPressing != pressing else { return }
        pressing = newPressing
        rebuild()
    }

    private func rebuild() {
        build()
        setArtwork(artwork)
        setSpinning(isSpinning)
    }

    func setArtwork(_ image: NSImage?) {
        let art = image ?? GenerativeCover.make(seed: "spindle").image
        artwork = art
        deck.labelMaterial.diffuse.contents = art
        sleeveMaterial?.diffuse.contents = art
    }

    /// Put a cover on the pile beside the deck. Neither Music nor Spotify
    /// will say what is coming next, so the stack shows what just finished,
    /// which is what a pile of records beside a turntable actually is.
    func setLastPlayed(_ image: NSImage?) {
        lastPlayedArtwork = image
        guard let image else { return }
        stackCoverMaterial?.diffuse.contents = image
    }

    /// Start or stop the platter.
    ///
    /// A platter has mass. It does not arrive at 33 1/3 the instant the motor
    /// is switched on, and it does not stop dead when the motor cuts: the belt
    /// brings it up over a second or so, and a heavy platter then coasts for
    /// several more. Snapping between nothing and full speed was one of the
    /// clearest signs that none of this was a real machine.
    func setSpinning(_ spinning: Bool) {
        guard spinning != isSpinning else { return }
        isSpinning = spinning
        deck.spinNode.removeAction(forKey: Self.spinKey)
        if spinning {
            runSpinUp()
        } else {
            runCoastDown()
        }
        setWarpWobble(spinning)
    }

    private static let spinKey = "spin"

    /// Angular speed in radians per second.
    private var targetSpeed: CGFloat { 2 * .pi * rpm / 60 }

    /// Belt drive: speed approaches the target exponentially, so the angle is
    /// the integral of that approach rather than a straight ramp.
    private func runSpinUp() {
        let omega = targetSpeed
        let tau = Self.spinUpTau
        let start = deck.spinNode.eulerAngles.y

        let ramp = SCNAction.customAction(duration: tau * 5) { node, elapsed in
            let t = TimeInterval(elapsed)
            let turned = omega * CGFloat(t - tau * (1 - exp(-t / tau)))
            node.eulerAngles.y = start - turned
        }

        deck.spinNode.runAction(ramp, forKey: Self.spinKey) { [weak self] in
            guard let self, self.isSpinning else { return }
            // Close enough to speed now; hand over to a constant turn.
            let turn = SCNAction.rotateBy(x: 0, y: -.pi * 2, z: 0,
                                          duration: TimeInterval(60 / self.rpm))
            turn.timingMode = .linear
            self.deck.spinNode.runAction(.repeatForever(turn), forKey: Self.spinKey)
        }
    }

    /// Free-wheeling: friction alone, so speed decays and the platter creeps
    /// to a halt rather than stopping on the beat.
    private func runCoastDown() {
        let omega = targetSpeed
        let tau = Self.coastTau
        let start = deck.spinNode.eulerAngles.y

        let coast = SCNAction.customAction(duration: tau * 4) { node, elapsed in
            let t = TimeInterval(elapsed)
            let turned = omega * CGFloat(tau * (1 - exp(-t / tau)))
            node.eulerAngles.y = start - turned
        }
        deck.spinNode.runAction(coast, forKey: Self.spinKey)
    }

    /// The stylus riding the warp, once per revolution.
    private func setWarpWobble(_ on: Bool) {
        deck.tonearmWarp.removeAction(forKey: Self.warpKey)
        guard on else {
            deck.tonearmWarp.eulerAngles.x = 0
            return
        }
        let period = TimeInterval(60 / rpm)
        let bob = SCNAction.customAction(duration: period) { node, elapsed in
            let phase = Double(elapsed) / period * 2 * .pi
            node.eulerAngles.x = Self.warpAmplitude * CGFloat(sin(phase))
        }
        deck.tonearmWarp.runAction(.repeatForever(bob), forKey: Self.warpKey)
    }

    private static let warpKey = "warp"
    /// How far the arm rises on the high side of the warp.
    private static let warpAmplitude: CGFloat = 0.0022
    /// How quickly the belt brings the platter up to speed.
    private static let spinUpTau: TimeInterval = 0.62
    /// How long the platter free-wheels once the motor cuts.
    private static let coastTau: TimeInterval = 1.45

    func setRPM(_ value: CGFloat) {
        rpm = max(1, value)
        if isSpinning { setSpinning(true) }
    }

    /// Move the stylus to match how far into the side we are (0...1).
    func setProgress(_ progress: Double, animated: Bool = true) {
        let t = CGFloat(min(max(progress, 0), 1))
        // Lead-in groove to run-out groove, in metres from the spindle.
        let radius = 0.1430 - t * (0.1430 - 0.0580)
        setArmLifted(false, animated: animated)
        setTonearmYaw(DeckMetrics.tonearmYaw(forStylusRadius: radius),
                      duration: animated ? 0.9 : 0)
    }

    /// Cue the arm up and swing it back to its rest, the way you would when
    /// the music stops. The lift leads the swing slightly, because dragging a
    /// stylus sideways across a record is the one thing you never do.
    func parkTonearm(animated: Bool = true) {
        setArmLifted(true, animated: animated)
        setTonearmYaw(DeckMetrics.tonearmYaw(forStylusRadius: DeckMetrics.parkRadius),
                      duration: animated ? 1.1 : 0)
    }

    /// Raise or lower the stylus. About two degrees at the bearing, which is
    /// eight millimetres at the stylus: what a real cueing lever gives you.
    private func setArmLifted(_ lifted: Bool, animated: Bool) {
        guard lifted != isArmLifted else { return }
        isArmLifted = lifted
        let angle: CGFloat = lifted ? 0.035 : 0
        guard animated else {
            deck.tonearmLift.eulerAngles.x = angle
            return
        }
        SCNTransaction.begin()
        // A cueing lever is a viscous damper. It lifts briskly and settles,
        // and lowers slowly: the whole point of the mechanism is that the
        // stylus is never dropped onto the record.
        if lifted {
            SCNTransaction.animationDuration = 0.42
            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.36, 1.0)
        } else {
            SCNTransaction.animationDuration = 1.15
            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction(controlPoints: 0.45, 0.02, 0.70, 0.62)
        }
        deck.tonearmLift.eulerAngles.x = angle
        SCNTransaction.commit()
    }

    private func setTonearmYaw(_ yaw: CGFloat, duration: TimeInterval) {
        guard duration > 0 else {
            deck.tonearmPivot.eulerAngles.y = yaw
            return
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        deck.tonearmPivot.eulerAngles.y = yaw
        SCNTransaction.commit()
    }

    // MARK: Build

    private var sleeveMaterial: SCNMaterial?
    private var stackCoverMaterial: SCNMaterial?
    /// The cover of the last thing played, waiting on the pile.
    private var lastPlayedArtwork: NSImage?

    private func build() {
        world.childNodes.forEach { $0.removeFromParentNode() }
        sleeveMaterial = nil
        stackCoverMaterial = nil

        configureEnvironment()
        configureCamera()
        addLights()
        addRoom()

        deck = Deck(preset: preset, artwork: artwork, pressing: pressing)
        deck.node.eulerAngles = SCNVector3(0, preset.deckYaw, 0)
        world.addChildNode(deck.node)

        addDressing()
        addDust()
        // The deck is new, so the stored lift state no longer describes it.
        isArmLifted = false
        parkTonearm(animated: false)
    }

    private func configureEnvironment() {
        scene.background.contents = Textures.backdrop(preset: preset)
        scene.lightingEnvironment.contents = Textures.environment(preset: preset)
        scene.lightingEnvironment.intensity =
            preset.environmentIntensity * SceneTuning.environmentScale
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = preset.fieldOfView
        camera.projectionDirection = .horizontal
        camera.zNear = 0.01
        camera.zFar = 30

        camera.wantsHDR = SceneTuning.toneMapping
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = preset.exposure + (SceneTuning.exposureOffset ?? 0)
        if let gray = SceneTuning.averageGray { camera.averageGray = gray }
        if let white = SceneTuning.whitePoint { camera.whitePoint = white }

        camera.bloomIntensity = preset.bloom
        camera.bloomThreshold = 0.92
        camera.bloomBlurRadius = 18
        camera.vignettingIntensity = preset.vignette
        camera.vignettingPower = 1.25
        // A trace of lens error. Perfectly rectilinear, perfectly achromatic
        // images are the ones that read as computer-generated.
        camera.colorFringeStrength = 0.55
        camera.saturation = 1.03
        camera.contrast = 0.1
        camera.grainIntensity = 0.26
        camera.grainScale = 1.2
        camera.grainIsColored = false
        // A record turning at 33 rpm smears at the rim. Only the live view
        // sees this: a still has no previous frame to blur against.
        camera.motionBlurIntensity = 1.1

        // Contact shadows, without which nothing sits on the desk.
        camera.screenSpaceAmbientOcclusionIntensity = 1.9
        camera.screenSpaceAmbientOcclusionRadius = 0.09
        camera.screenSpaceAmbientOcclusionBias = 0.012

        if preset.fStop > 0 {
            camera.wantsDepthOfField = true
            camera.focusDistance = preset.focusDistance
            camera.fStop = preset.fStop
            camera.apertureBladeCount = 7
        }

        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        // Roll lives on the child so it does not fight the look-at constraint.
        cameraNode.eulerAngles = SCNVector3(0, 0, preset.roll)

        lookTarget.position = vector(preset.cameraTarget)
        cameraRig.position = vector(preset.cameraPosition)
        let lookAt = SCNLookAtConstraint(target: lookTarget)
        lookAt.isGimbalLockEnabled = true
        cameraRig.constraints = [lookAt]
    }

    // MARK: Light

    private func addLights() {
        for spec in [preset.key, preset.fillLight, preset.bounceLight] {
            world.addChildNode(makeLight(spec))
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = Textures.solid(preset.ambient)
        ambient.intensity = preset.ambientIntensity * SceneTuning.lightScale
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        world.addChildNode(ambientNode)
    }

    private func makeLight(_ spec: ScenePreset.Light) -> SCNNode {
        let light = SCNLight()
        light.color = Textures.solid(spec.color)
        light.intensity = spec.intensity * SceneTuning.lightScale
        light.castsShadow = spec.castsShadow
        light.shadowMode = .deferred
        light.shadowRadius = spec.shadowRadius
        light.shadowSampleCount = 48
        light.shadowColor = NSColor(white: 0, alpha: 0.66)
        light.shadowMapSize = CGSize(width: 2048, height: 2048)

        switch spec.kind {
        case .area(let width, let height):
            light.type = .area
            light.areaType = .rectangle
            light.areaExtents = simd_float3(Float(width), Float(height), 0)
            // Area shadows are expensive and often redundant next to the key.
            light.castsShadow = spec.castsShadow
        case .spot(let angle):
            light.type = .spot
            light.spotInnerAngle = angle * 0.75
            light.spotOuterAngle = angle
            light.zNear = 0.05
            light.zFar = 6
            // What the light arrives through. A bare cone is a stage light;
            // slats or panes make it a room.
            switch spec.gobo {
            case .none:
                break
            case .window:
                light.gobo?.contents = Textures.windowGobo()
            case .blinds:
                light.gobo?.contents = Textures.blindGobo()
            }
            light.gobo?.wrapS = .clamp
            light.gobo?.wrapT = .clamp
        case .omni:
            light.type = .omni
        }

        let node = SCNNode()
        node.light = light
        node.position = vector(spec.position)
        if case .omni = spec.kind {} else {
            let aim = SCNNode()
            aim.position = vector(spec.target)
            world.addChildNode(aim)
            node.constraints = [SCNLookAtConstraint(target: aim)]
        }
        return node
    }

    // MARK: Room

    private func addRoom() {
        // Desk. Thicker than it needs to be, because the front edge is in
        // frame and a thin slab reads as cardboard.
        let desk = SCNBox(width: 3.2, height: 0.042, length: 1.25, chamferRadius: 0.0035)
        let top = Materials.varnishedWood(base: preset.deskBase, grain: preset.deskGrain,
                                          gloss: preset.deskGloss)
        top.diffuse.contentsTransform = SCNMatrix4MakeScale(2.6, 1, 1)
        top.roughness.contentsTransform = SCNMatrix4MakeScale(2.6, 1, 1)
        desk.materials = [top]
        let deskNode = SCNNode(geometry: desk)
        deskNode.position = SCNVector3(0, -0.021, 0.12)
        world.addChildNode(deskNode)

        // The apron under the desk edge, so the desk has a thickness.
        let apron = SCNBox(width: 3.2, height: 0.075, length: 0.030, chamferRadius: 0.002)
        apron.firstMaterial = Materials.varnishedWood(base: preset.deskBase.scaled(0.8),
                                                      grain: preset.deskGrain.scaled(0.8),
                                                      seed: 19)
        let apronNode = SCNNode(geometry: apron)
        apronNode.position = SCNVector3(0, -0.079, 0.12 + 1.25 / 2 - 0.015)
        world.addChildNode(apronNode)

        guard preset.dressing.wall else { return }

        let wall = SCNPlane(width: 7, height: 4)
        let plaster = Materials.mattePaint(preset.wallTop, seed: 881, wear: 1.6)
        plaster.diffuse.contents = Textures.plaster(preset: preset)
        wall.firstMaterial = plaster
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = SCNVector3(0, 1.2, -0.62)
        world.addChildNode(wallNode)

        // Skirting board: a small thing that makes a plane read as a wall.
        let skirting = SCNBox(width: 7, height: 0.085, length: 0.014, chamferRadius: 0.003)
        skirting.firstMaterial = Materials.mattePaint(preset.wallTop.scaled(1.1), seed: 882)
        let skirtingNode = SCNNode(geometry: skirting)
        skirtingNode.position = SCNVector3(0, -0.30, -0.60)
        world.addChildNode(skirtingNode)
    }

    // MARK: Dressing

    private func addDressing() {
        let dressing = preset.dressing
        let props = Props(preset: preset, pressing: pressing)

        if dressing.sleeve {
            let sleeve = dressing.sleeveStand
                ? props.sleeveStand(artwork: artwork)
                : props.sleeve(artwork: artwork)
            sleeveMaterial = sleeve.material
            if dressing.sleeveStand {
                sleeve.node.position = SCNVector3(-0.368, 0, -0.215)
                sleeve.node.eulerAngles = SCNVector3(0, 0.10, 0)
            } else {
                sleeve.node.position = SCNVector3(-0.352, 0.160, -0.165)
                sleeve.node.eulerAngles = SCNVector3(-0.125, 0.36, 0.02)
            }
            world.addChildNode(sleeve.node)
        }
        if dressing.leaningFrame {
            let frame = props.leaningFrame()
            frame.position = SCNVector3(0.405, 0, -0.282)
            frame.eulerAngles = SCNVector3(0, -0.16, 0)
            world.addChildNode(frame)
        }
        if dressing.stack {
            let stack = props.recordStack()
            stackCoverMaterial = stack.topCover
            if let lastPlayedArtwork {
                stack.topCover.diffuse.contents = lastPlayedArtwork
            }
            stack.node.position = SCNVector3(0.395, 0, 0.165)
            stack.node.eulerAngles = SCNVector3(0, -0.44, 0)
            world.addChildNode(stack.node)
        }
        if dressing.mug {
            let mug = props.mug()
            mug.position = SCNVector3(-0.258, 0, -0.218)
            // Handle roughly side on, which reads from either side of the room.
            mug.eulerAngles = SCNVector3(0, 2.25, 0)
            world.addChildNode(mug)
        }
        if dressing.plant {
            let plant = props.plant()
            plant.position = SCNVector3(-0.600, 0, -0.195)
            world.addChildNode(plant)
        }
        if dressing.bigPlant {
            let plant = props.bigPlant()
            plant.position = SCNVector3(0.605, 0, -0.230)
            plant.eulerAngles = SCNVector3(0, 0.6, 0)
            world.addChildNode(plant)
        }
        if dressing.books {
            let books = props.books()
            books.position = SCNVector3(0.470, 0, -0.295)
            books.eulerAngles = SCNVector3(0, 0.18, 0)
            world.addChildNode(books)
        }
        if dressing.headphones {
            let cans = props.headphones()
            cans.position = SCNVector3(-0.470, 0, -0.230)
            cans.eulerAngles = SCNVector3(0, 0.95, 0)
            world.addChildNode(cans)
        }
        if dressing.lamp {
            let lamp = props.lamp()
            lamp.position = SCNVector3(0.600, 0, -0.270)
            world.addChildNode(lamp)
        }
        if dressing.framedArt {
            // Hung low, the way art sits above a sideboard, and small enough
            // to clear the top of a 16:9 frame on a lens this long.
            let frame = props.framedArt(width: 0.250, height: 0.310)
            frame.position = SCNVector3(0.300, 0.440, -0.598)
            frame.eulerAngles = SCNVector3(0.015, 0, 0)
            world.addChildNode(frame)
        }
        if dressing.shelf {
            let shelf = props.shelf()
            shelf.position = SCNVector3(0.620, 0.520, -0.555)
            world.addChildNode(shelf)
        }
    }

    // MARK: Dust

    private func addDust() {
        guard preset.dustCount > 0 else { return }
        let system = SCNParticleSystem()
        system.birthRate = CGFloat(preset.dustCount) / 9.0
        system.particleLifeSpan = 9
        system.particleLifeSpanVariation = 5
        system.particleSize = 0.0011
        system.particleSizeVariation = 0.0011
        system.particleColor = Textures.solid(preset.dustColor)
        system.particleColorVariation = SCNVector4(0.02, 0.05, 0.08, 0.3)
        system.particleVelocity = 0.006
        system.particleVelocityVariation = 0.010
        system.spreadingAngle = 180
        system.emitterShape = SCNBox(width: 1.0, height: 0.5, length: 0.6, chamferRadius: 0)
        system.birthLocation = .volume
        system.birthDirection = .random
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.particleImage = Textures.nsImage(softDot())
        system.sortingMode = .none
        system.particleIntensity = 0.5

        let node = SCNNode()
        node.position = SCNVector3(0, 0.22, 0.14)
        node.addParticleSystem(system)
        world.addChildNode(node)
    }

    /// A soft round sprite for the dust. Drawn rather than shipped.
    private func softDot(size: Int = 32) -> CGImage {
        Textures.image(width: size, height: size) { u, v in
            let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
            let a = max(0, 1 - d)
            return (1, 1, 1, a * a)
        }
    }

    private func vector(_ v: Vec3) -> SCNVector3 {
        SCNVector3(v.x, v.y, v.z)
    }
}
