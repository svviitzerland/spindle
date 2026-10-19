import AppKit
import SceneKit

/// Measurements of the deck, in metres, taken from a real belt-drive player.
///
/// Honest dimensions matter more than they look: a 12-inch record is 0.30 m
/// across and a tonearm is 0.235 m from pivot to stylus, and once those are
/// right the lighting and the perspective fall into place without fudging.
enum DeckMetrics {
    static let recordRadius: CGFloat = 0.1495
    static let recordThickness: CGFloat = 0.0019
    static let labelRadius: CGFloat = 0.0505
    static let slipmatRadius: CGFloat = 0.1510
    static let slipmatThickness: CGFloat = 0.0022
    static let platterRadius: CGFloat = 0.1545
    static let platterHeight: CGFloat = 0.0205

    static let plinthWidth: CGFloat = 0.445
    static let plinthHeight: CGFloat = 0.062
    static let plinthDepth: CGFloat = 0.358
    static let footHeight: CGFloat = 0.0145
    static let footRadius: CGFloat = 0.0135

    static let armLength: CGFloat = 0.235

    /// Where the platter's axis stands, relative to the deck's centre.
    static let spindle = CGPoint(x: -0.048, y: 0.012)
    /// Where the tonearm is bolted down.
    static let pivot = CGPoint(x: 0.157, y: -0.122)

    static let plinthBottom = footHeight
    static let plinthTop = plinthBottom + plinthHeight
    static let platterTop = plinthTop + platterHeight
    static let recordBottom = platterTop + slipmatThickness
    static let recordTop = recordBottom + recordThickness

    /// Solve the pivot angle that lands the stylus `radius` from the spindle.
    ///
    /// Pivot, spindle and stylus form a triangle with two known sides, so the
    /// law of cosines gives the angle outright — and the arc the arm sweeps is
    /// then the same one a real arm sweeps, about 21 degrees across a side.
    static func tonearmYaw(forStylusRadius radius: CGFloat) -> CGFloat {
        let dx = spindle.x - pivot.x
        let dz = spindle.y - pivot.y
        let d = (dx * dx + dz * dz).squareRoot()
        let cosTheta = (armLength * armLength + d * d - radius * radius) / (2 * armLength * d)
        let theta = acos(min(max(cosTheta, -1), 1))
        // The arm is modelled pointing down its own -Z, so this is the heading
        // from pivot to spindle, opened out toward the near edge of the record.
        return atan2(-dx, -dz) + theta
    }
}

/// Builds the turntable itself: plinth, platter, record and arm.
///
/// Separated from the room so the two can be read independently — this file is
/// all object detail, `TurntableScene` is all staging.
final class Deck {

    let node = SCNNode()
    /// Carries the record and label; this is what turns.
    let spinNode = SCNNode()
    /// Carries the whole arm assembly; its yaw is the tracking angle.
    let tonearmPivot = SCNNode()
    let labelMaterial: SCNMaterial

    private let preset: ScenePreset
    private let pressing: Pressing

    init(preset: ScenePreset, artwork: NSImage, pressing: Pressing = .black) {
        self.preset = preset
        self.pressing = pressing
        // A pressing with its own label art is meant to be looked at rather
        // than listened to, so it wins over the album cover.
        let labelArt = pressing.labelImage.flatMap(NSImage.init(contentsOf:)) ?? artwork
        labelMaterial = Materials.paperboard(labelArt, seed: 3131)

        addFeet()
        addPlinth()
        addPlatter()
        addRecord()
        addTonearm()
        addControls()
        addCable()
    }

    // MARK: Plinth

    /// Four rubber feet, which matter more than they sound: they lift the
    /// plinth off the desk and open a shadow gap underneath. Without that gap
    /// the deck reads as painted onto the wood.
    private func addFeet() {
        let rubber = Materials.rubber(RGB(0.045, 0.043, 0.042))
        let inset: CGFloat = 0.038
        for sx in [-1.0, 1.0] as [CGFloat] {
            for sz in [-1.0, 1.0] as [CGFloat] {
                let foot = SCNCylinder(radius: DeckMetrics.footRadius,
                                       height: DeckMetrics.footHeight)
                foot.radialSegmentCount = 32
                foot.firstMaterial = rubber
                let footNode = SCNNode(geometry: foot)
                footNode.position = SCNVector3(
                    sx * (DeckMetrics.plinthWidth / 2 - inset),
                    DeckMetrics.footHeight / 2,
                    sz * (DeckMetrics.plinthDepth / 2 - inset))
                footNode.castsShadow = true
                node.addChildNode(footNode)
            }
        }
    }

    private func addPlinth() {
        // A generous chamfer. Real cabinets have no sharp edges, and the thin
        // highlight along a chamfer is most of what communicates solidity.
        let body = SCNBox(width: DeckMetrics.plinthWidth,
                          height: DeckMetrics.plinthHeight,
                          length: DeckMetrics.plinthDepth,
                          chamferRadius: 0.0045)
        body.chamferSegmentCount = 8
        body.firstMaterial = Materials.mattePaint(preset.plinth)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, DeckMetrics.plinthBottom + DeckMetrics.plinthHeight / 2, 0)
        bodyNode.castsShadow = true
        node.addChildNode(bodyNode)

        // A top plate sitting slightly proud, so the top is a surface rather
        // than the end of a block.
        let plate = SCNBox(width: DeckMetrics.plinthWidth - 0.012,
                           height: 0.0035,
                           length: DeckMetrics.plinthDepth - 0.012,
                           chamferRadius: 0.0015)
        plate.firstMaterial = Materials.mattePaint(preset.plinth.scaled(1.06), seed: 44)
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, DeckMetrics.plinthTop + 0.0012, 0)
        node.addChildNode(plateNode)

        // Recessed well under the platter: a real plinth is not flat there.
        let well = SCNCylinder(radius: DeckMetrics.platterRadius + 0.006, height: 0.004)
        well.radialSegmentCount = 64
        well.firstMaterial = Materials.mattePaint(preset.plinth.scaled(0.82), seed: 45)
        let wellNode = SCNNode(geometry: well)
        wellNode.position = SCNVector3(DeckMetrics.spindle.x,
                                       DeckMetrics.plinthTop,
                                       DeckMetrics.spindle.y)
        node.addChildNode(wellNode)
    }

    // MARK: Platter

    private func addPlatter() {
        let metal = Materials.brushedMetal(tint: preset.platter)

        let platter = SCNCylinder(radius: DeckMetrics.platterRadius,
                                  height: DeckMetrics.platterHeight)
        platter.radialSegmentCount = 120
        platter.materials = [metal, metal, metal]
        let platterNode = SCNNode(geometry: platter)
        platterNode.position = SCNVector3(DeckMetrics.spindle.x,
                                          DeckMetrics.plinthTop + DeckMetrics.platterHeight / 2,
                                          DeckMetrics.spindle.y)
        platterNode.castsShadow = true
        node.addChildNode(platterNode)

        // Machined rim: catches the key light as a bright ring and does more
        // for the sense of metal than any amount of roughness tuning.
        let rim = SCNTorus(ringRadius: DeckMetrics.platterRadius - 0.0012, pipeRadius: 0.0014)
        rim.ringSegmentCount = 120
        rim.pipeSegmentCount = 12
        rim.firstMaterial = Materials.machinedMetal(tint: preset.platter.scaled(1.1),
                                                    roughness: 0.14)
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(DeckMetrics.spindle.x,
                                      DeckMetrics.platterTop - 0.0012,
                                      DeckMetrics.spindle.y)
        node.addChildNode(rimNode)

        // Felt slip mat.
        let mat = SCNCylinder(radius: DeckMetrics.slipmatRadius,
                              height: DeckMetrics.slipmatThickness)
        mat.radialSegmentCount = 96
        let feltMaterial = Materials.felt(RGB(0.055, 0.052, 0.058))
        mat.materials = [feltMaterial, feltMaterial, feltMaterial]
        let matNode = SCNNode(geometry: mat)
        matNode.position = SCNVector3(DeckMetrics.spindle.x,
                                      DeckMetrics.platterTop + DeckMetrics.slipmatThickness / 2,
                                      DeckMetrics.spindle.y)
        node.addChildNode(matNode)
    }

    // MARK: Record

    private func addRecord() {
        spinNode.position = SCNVector3(DeckMetrics.spindle.x,
                                       DeckMetrics.recordBottom,
                                       DeckMetrics.spindle.y)
        node.addChildNode(spinNode)

        let vinyl = Materials.vinyl(pressing)
        let edge = Materials.vinylEdge(pressing)

        let record = SCNCylinder(radius: DeckMetrics.recordRadius,
                                 height: DeckMetrics.recordThickness)
        record.radialSegmentCount = 160
        record.materials = [edge, vinyl, vinyl]
        let recordNode = SCNNode(geometry: record)
        recordNode.position = SCNVector3(0, DeckMetrics.recordThickness / 2, 0)
        recordNode.castsShadow = true
        spinNode.addChildNode(recordNode)

        // The raised outer rim and the raised land around the label: a record
        // only touches the mat at those two rings, and the highlight they catch
        // is one of its most recognisable features.
        for radius in [DeckMetrics.recordRadius - 0.0016,
                       DeckMetrics.labelRadius + 0.0042] {
            let ring = SCNTorus(ringRadius: radius, pipeRadius: 0.0009)
            ring.ringSegmentCount = 140
            ring.pipeSegmentCount = 10
            ring.firstMaterial = vinyl
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(0, DeckMetrics.recordThickness, 0)
            spinNode.addChildNode(ringNode)
        }

        let label = SCNCylinder(radius: DeckMetrics.labelRadius, height: 0.0005)
        label.radialSegmentCount = 96
        let labelEdge = Materials.paperboard(Textures.solid(RGB(0.86, 0.84, 0.80)), seed: 11)
        label.materials = [labelEdge, labelMaterial, labelMaterial]
        let labelNode = SCNNode(geometry: label)
        labelNode.position = SCNVector3(0, DeckMetrics.recordThickness + 0.00025, 0)
        spinNode.addChildNode(labelNode)

        // Spindle pin, and the hole it passes through.
        let hole = SCNCylinder(radius: 0.0037, height: 0.0012)
        hole.firstMaterial = Materials.plastic(RGB(0.02, 0.02, 0.02), gloss: 0.1)
        let holeNode = SCNNode(geometry: hole)
        holeNode.position = SCNVector3(0, DeckMetrics.recordThickness, 0)
        spinNode.addChildNode(holeNode)

        let pin = SCNCylinder(radius: 0.0034, height: 0.0165)
        pin.radialSegmentCount = 24
        pin.firstMaterial = Materials.machinedMetal(tint: preset.metal, roughness: 0.12)
        let pinNode = SCNNode(geometry: pin)
        pinNode.position = SCNVector3(DeckMetrics.spindle.x,
                                      DeckMetrics.recordTop + 0.0062,
                                      DeckMetrics.spindle.y)
        node.addChildNode(pinNode)
    }

    // MARK: Tonearm

    private func addTonearm() {
        let metal = Materials.machinedMetal(tint: preset.metal, roughness: 0.15)
        let dark = Materials.plastic(RGB(0.055, 0.053, 0.056), gloss: 0.42)
        let base = DeckMetrics.plinthTop

        // Pivot tower, built as a stack rather than one cylinder so it reads
        // as machined parts bolted together.
        let collar = SCNCylinder(radius: 0.0215, height: 0.006)
        collar.radialSegmentCount = 40
        collar.firstMaterial = metal
        let collarNode = SCNNode(geometry: collar)
        collarNode.position = SCNVector3(DeckMetrics.pivot.x, base + 0.003, DeckMetrics.pivot.y)
        node.addChildNode(collarNode)

        let post = SCNCylinder(radius: 0.0135, height: 0.046)
        post.radialSegmentCount = 36
        post.firstMaterial = dark
        let postNode = SCNNode(geometry: post)
        postNode.position = SCNVector3(DeckMetrics.pivot.x, base + 0.029, DeckMetrics.pivot.y)
        node.addChildNode(postNode)

        // Everything beyond here turns with the arm.
        tonearmPivot.position = SCNVector3(DeckMetrics.pivot.x, base + 0.055, DeckMetrics.pivot.y)
        node.addChildNode(tonearmPivot)

        let gimbal = SCNBox(width: 0.026, height: 0.020, length: 0.024, chamferRadius: 0.004)
        gimbal.firstMaterial = metal
        tonearmPivot.addChildNode(SCNNode(geometry: gimbal))

        let yoke = SCNCylinder(radius: 0.0062, height: 0.034)
        yoke.firstMaterial = metal
        let yokeNode = SCNNode(geometry: yoke)
        yokeNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        tonearmPivot.addChildNode(yokeNode)

        // The tube tapers, as real arms do. Modelled down -Z so the yaw solver
        // in DeckMetrics stays readable.
        let tube = SCNCone(topRadius: 0.0030, bottomRadius: 0.0050,
                           height: DeckMetrics.armLength)
        tube.radialSegmentCount = 28
        tube.firstMaterial = metal
        let tubeNode = SCNNode(geometry: tube)
        tubeNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        tubeNode.position = SCNVector3(0, -0.0045, -DeckMetrics.armLength / 2)
        tubeNode.castsShadow = true
        tonearmPivot.addChildNode(tubeNode)

        // Headshell, cartridge, stylus and finger lift.
        let headshell = SCNBox(width: 0.0195, height: 0.0085, length: 0.030, chamferRadius: 0.0022)
        headshell.firstMaterial = metal
        let headNode = SCNNode(geometry: headshell)
        headNode.position = SCNVector3(0, -0.0125, -DeckMetrics.armLength + 0.014)
        headNode.eulerAngles = SCNVector3(-0.1, 0, 0)
        tonearmPivot.addChildNode(headNode)

        let cartridge = SCNBox(width: 0.0135, height: 0.0095, length: 0.0185, chamferRadius: 0.0012)
        cartridge.firstMaterial = Materials.plastic(RGB(0.14, 0.035, 0.035), gloss: 0.6, seed: 91)
        let cartridgeNode = SCNNode(geometry: cartridge)
        cartridgeNode.position = SCNVector3(0, -0.0205, -DeckMetrics.armLength + 0.012)
        cartridgeNode.eulerAngles = SCNVector3(-0.1, 0, 0)
        tonearmPivot.addChildNode(cartridgeNode)

        let stylus = SCNCone(topRadius: 0.0011, bottomRadius: 0.0001, height: 0.0062)
        stylus.firstMaterial = metal
        let stylusNode = SCNNode(geometry: stylus)
        stylusNode.position = SCNVector3(0, -0.0272, -DeckMetrics.armLength + 0.0045)
        tonearmPivot.addChildNode(stylusNode)

        // Finger lift: a small tab everyone has grabbed a thousand times.
        let lift = SCNBox(width: 0.0022, height: 0.012, length: 0.0075, chamferRadius: 0.0008)
        lift.firstMaterial = metal
        let liftNode = SCNNode(geometry: lift)
        liftNode.position = SCNVector3(0.0105, -0.0105, -DeckMetrics.armLength + 0.020)
        liftNode.eulerAngles = SCNVector3(0, 0, 0.42)
        tonearmPivot.addChildNode(liftNode)

        // Counterweight and its stub.
        let stub = SCNCylinder(radius: 0.0036, height: 0.052)
        stub.firstMaterial = metal
        let stubNode = SCNNode(geometry: stub)
        stubNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        stubNode.position = SCNVector3(0, 0, 0.026)
        tonearmPivot.addChildNode(stubNode)

        let weight = SCNCylinder(radius: 0.0182, height: 0.0245)
        weight.radialSegmentCount = 44
        weight.firstMaterial = dark
        let weightNode = SCNNode(geometry: weight)
        weightNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        weightNode.position = SCNVector3(0, 0, 0.047)
        weightNode.castsShadow = true
        tonearmPivot.addChildNode(weightNode)

        // Tracking-force dial on the face of the weight.
        let dial = SCNTorus(ringRadius: 0.0128, pipeRadius: 0.0022)
        dial.firstMaterial = metal
        let dialNode = SCNNode(geometry: dial)
        dialNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        dialNode.position = SCNVector3(0, 0, 0.0345)
        tonearmPivot.addChildNode(dialNode)

        addArmRestAndControls(base: base, metal: metal, dark: dark)
    }

    /// Anti-skate, cueing lever and the rest — the fittings crowded around the
    /// pivot that tell you this is a machine and not a prop.
    private func addArmRestAndControls(base: CGFloat, metal: SCNMaterial, dark: SCNMaterial) {
        // Anti-skate dial.
        let antiSkate = SCNCylinder(radius: 0.0088, height: 0.009)
        antiSkate.radialSegmentCount = 28
        antiSkate.firstMaterial = metal
        let antiSkateNode = SCNNode(geometry: antiSkate)
        antiSkateNode.position = SCNVector3(DeckMetrics.pivot.x + 0.030, base + 0.0045,
                                            DeckMetrics.pivot.y + 0.012)
        node.addChildNode(antiSkateNode)

        // Cueing lever: post plus the little paddle you actually push.
        let cuePost = SCNCylinder(radius: 0.0062, height: 0.016)
        cuePost.firstMaterial = metal
        let cuePostNode = SCNNode(geometry: cuePost)
        cuePostNode.position = SCNVector3(DeckMetrics.pivot.x - 0.030, base + 0.008,
                                          DeckMetrics.pivot.y + 0.026)
        node.addChildNode(cuePostNode)

        let paddle = SCNBox(width: 0.0068, height: 0.0052, length: 0.024, chamferRadius: 0.0018)
        paddle.firstMaterial = dark
        let paddleNode = SCNNode(geometry: paddle)
        paddleNode.position = SCNVector3(DeckMetrics.pivot.x - 0.030, base + 0.018,
                                         DeckMetrics.pivot.y + 0.036)
        paddleNode.eulerAngles = SCNVector3(0.22, 0, 0)
        node.addChildNode(paddleNode)

        // Arm rest with its clip.
        let restPost = SCNCylinder(radius: 0.0048, height: 0.030)
        restPost.firstMaterial = metal
        let restNode = SCNNode(geometry: restPost)
        restNode.position = SCNVector3(DeckMetrics.pivot.x - 0.052, base + 0.015,
                                       DeckMetrics.pivot.y + 0.090)
        node.addChildNode(restNode)

        let clip = SCNBox(width: 0.0115, height: 0.0075, length: 0.0115, chamferRadius: 0.0028)
        clip.firstMaterial = dark
        let clipNode = SCNNode(geometry: clip)
        clipNode.position = SCNVector3(DeckMetrics.pivot.x - 0.052, base + 0.0335,
                                       DeckMetrics.pivot.y + 0.090)
        node.addChildNode(clipNode)
    }

    // MARK: Controls

    private func addControls() {
        let base = DeckMetrics.plinthTop
        let metal = Materials.machinedMetal(tint: preset.metal, roughness: 0.2)

        // Speed selector, with a knurled collar and an index mark.
        let knob = SCNCylinder(radius: 0.0168, height: 0.0115)
        knob.radialSegmentCount = 44
        knob.firstMaterial = metal
        let knobNode = SCNNode(geometry: knob)
        knobNode.position = SCNVector3(0.152, base + 0.0058, 0.118)
        knobNode.castsShadow = true
        node.addChildNode(knobNode)

        let knurl = SCNTorus(ringRadius: 0.0168, pipeRadius: 0.0018)
        knurl.ringSegmentCount = 48
        knurl.firstMaterial = Materials.machinedMetal(tint: preset.metal.scaled(0.8),
                                                      roughness: 0.34)
        let knurlNode = SCNNode(geometry: knurl)
        knurlNode.position = SCNVector3(0.152, base + 0.0058, 0.118)
        node.addChildNode(knurlNode)

        let mark = SCNBox(width: 0.0016, height: 0.0006, length: 0.0075, chamferRadius: 0)
        mark.firstMaterial = Materials.plastic(RGB(0.06, 0.06, 0.06), gloss: 0.2)
        let markNode = SCNNode(geometry: mark)
        markNode.position = SCNVector3(0.152, base + 0.0118, 0.1275)
        node.addChildNode(markNode)

        // Power rocker.
        let switchPlate = SCNBox(width: 0.021, height: 0.0032, length: 0.012, chamferRadius: 0.001)
        switchPlate.firstMaterial = Materials.plastic(RGB(0.09, 0.088, 0.09), gloss: 0.5)
        let switchNode = SCNNode(geometry: switchPlate)
        switchNode.position = SCNVector3(0.095, base + 0.0032, 0.146)
        switchNode.eulerAngles = SCNVector3(0.12, 0, 0)
        node.addChildNode(switchNode)

        // Power indicator. Small, warm, and the only thing in the scene that
        // emits its own light.
        let led = SCNSphere(radius: 0.0026)
        led.firstMaterial = Materials.emissive(RGB(1.0, 0.52, 0.20), intensity: 1.4)
        let ledNode = SCNNode(geometry: led)
        ledNode.position = SCNVector3(0.062, base + 0.0022, 0.1465)
        node.addChildNode(ledNode)

        // Maker's plate: blank, recessed, catching a highlight.
        let plate = SCNBox(width: 0.040, height: 0.0008, length: 0.0095, chamferRadius: 0.0003)
        plate.firstMaterial = Materials.machinedMetal(tint: preset.metal.scaled(0.9),
                                                      roughness: 0.28)
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(-0.155, base + 0.0028, 0.150)
        node.addChildNode(plateNode)
    }

    // MARK: Cable

    /// A signal lead falling off the back corner and onto the desk.
    ///
    /// Built as a chain of short cylinders following a catenary. It costs very
    /// little and it is one of the strongest cues that an object is physically
    /// present rather than placed: cables obey gravity, and the eye knows it.
    private func addCable() {
        let jacket = Materials.rubber(RGB(0.035, 0.034, 0.036), seed: 404)
        let start = SCNVector3(-0.150, DeckMetrics.plinthBottom + 0.012, -DeckMetrics.plinthDepth / 2)
        let end = SCNVector3(-0.345, 0.0022, -0.300)
        let sag: CGFloat = 0.030
        let segments = 16

        var previous = start
        for step in 1...segments {
            let t = CGFloat(step) / CGFloat(segments)
            // Linear path, pulled down by a parabola that vanishes at both ends.
            let droop = sag * 4 * t * (1 - t)
            let point = SCNVector3(start.x + (end.x - start.x) * t,
                                   max(start.y + (end.y - start.y) * t - droop, 0.0022),
                                   start.z + (end.z - start.z) * t)
            node.addChildNode(cableSegment(from: previous, to: point, material: jacket))
            previous = point
        }

        // The plug body where it leaves the plinth.
        let plug = SCNCylinder(radius: 0.0062, height: 0.016)
        plug.firstMaterial = Materials.machinedMetal(tint: RGB(0.68, 0.60, 0.40), roughness: 0.3)
        let plugNode = SCNNode(geometry: plug)
        plugNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        plugNode.position = SCNVector3(start.x, start.y, start.z - 0.006)
        node.addChildNode(plugNode)
    }

    private func cableSegment(from a: SCNVector3, to b: SCNVector3,
                              material: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = (dx * dx + dy * dy + dz * dz).squareRoot()
        let cylinder = SCNCylinder(radius: 0.0022, height: max(length, 0.0001))
        cylinder.radialSegmentCount = 10
        cylinder.firstMaterial = material
        let segment = SCNNode(geometry: cylinder)
        segment.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        // Cylinders stand along +Y, so aim one by yawing then pitching it.
        segment.eulerAngles = SCNVector3(
            -atan2(dz, (dx * dx + dy * dy).squareRoot()) - CGFloat.pi / 2,
            0,
            -atan2(dx, dy))
        return segment
    }
}
