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

    /// Height of the lift node above the plinth, where the arm hangs from.
    static let armPivotHeight: CGFloat = plinthTop + 0.0575

    /// Centre of the stylus cone in the lift node's own space, placed so the
    /// tip rests exactly on the playing surface.
    static let stylusHeightInArm: CGFloat = -(armPivotHeight - recordTop) + 0.0031

    /// How far forward that puts it, so the pivot-to-stylus distance really is
    /// `armLength` once the drop is accounted for.
    static var stylusReachInArm: CGFloat {
        // The pivot sits 1.5 mm below the lift node's origin.
        let drop = abs(stylusHeightInArm) - 0.0015
        return (armLength * armLength - drop * drop).squareRoot()
    }

    /// Where the stylus sits when the arm is off the record.
    static let parkRadius: CGFloat = recordRadius + 0.055

    /// Where the arm comes to rest on the deck.
    ///
    /// Derived from the park angle rather than placed by hand, so the cradle
    /// and the arm cannot disagree. They did: the rest was sitting 14 cm from
    /// where the arm actually stopped.
    static var armRestPosition: CGPoint {
        let yaw = tonearmYaw(forStylusRadius: parkRadius)
        let stylus = CGPoint(x: pivot.x - armLength * sin(yaw),
                             y: pivot.y - armLength * cos(yaw))
        // The cradle takes the tube a little behind the headshell.
        let dx = stylus.x - pivot.x, dz = stylus.y - pivot.y
        let length = (dx * dx + dz * dz).squareRoot()
        let behind: CGFloat = 0.032
        return CGPoint(x: stylus.x - dx / length * behind,
                       y: stylus.y - dz / length * behind)
    }

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
    /// Child of the pivot, rotating about the horizontal bearing. This is the
    /// cueing lift: raising it takes the stylus off the record.
    let tonearmLift = SCNNode()
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
        // Three materials, not one. A real arm is polished tube, darker
        // machined housings and a near-black counterweight, and that contrast
        // is most of what stops an assembly of cylinders reading as a toy.
        let tube = Materials.machinedMetal(tint: preset.metal, roughness: 0.11)
        let housing = Materials.machinedMetal(tint: preset.metal.scaled(0.52), roughness: 0.30)
        let dark = Materials.plastic(RGB(0.048, 0.046, 0.050), gloss: 0.55)
        let base = DeckMetrics.plinthTop

        // Pivot tower, stepped: a wide polished collar, a plain post, then the
        // bearing housing. One cylinder reads as a peg; three read as a part.
        let collar = SCNCylinder(radius: 0.0228, height: 0.0045)
        collar.radialSegmentCount = 48
        collar.firstMaterial = tube
        let collarNode = SCNNode(geometry: collar)
        collarNode.position = SCNVector3(DeckMetrics.pivot.x, base + 0.0022, DeckMetrics.pivot.y)
        node.addChildNode(collarNode)

        let post = SCNCylinder(radius: 0.0124, height: 0.030)
        post.radialSegmentCount = 36
        post.firstMaterial = housing
        let postNode = SCNNode(geometry: post)
        postNode.position = SCNVector3(DeckMetrics.pivot.x, base + 0.0195, DeckMetrics.pivot.y)
        node.addChildNode(postNode)

        let bearingHousing = SCNCylinder(radius: 0.0162, height: 0.0150)
        bearingHousing.radialSegmentCount = 44
        bearingHousing.firstMaterial = tube
        let housingNode = SCNNode(geometry: bearingHousing)
        housingNode.position = SCNVector3(DeckMetrics.pivot.x, base + 0.0420, DeckMetrics.pivot.y)
        node.addChildNode(housingNode)

        // Everything beyond here swings with the arm.
        tonearmPivot.position = SCNVector3(DeckMetrics.pivot.x, base + 0.0560, DeckMetrics.pivot.y)
        node.addChildNode(tonearmPivot)

        // Gimbal: two cheeks carrying a horizontal bearing, with a visible cap
        // on each side. This is the joint the arm actually pivots on, so it
        // has to look like a joint.
        for side in [-1.0, 1.0] as [CGFloat] {
            let cheek = SCNBox(width: 0.0042, height: 0.0175, length: 0.0135,
                               chamferRadius: 0.0012)
            cheek.firstMaterial = housing
            let cheekNode = SCNNode(geometry: cheek)
            cheekNode.position = SCNVector3(side * 0.0098, 0.0015, 0)
            tonearmPivot.addChildNode(cheekNode)

            let cap = SCNCylinder(radius: 0.0046, height: 0.0030)
            cap.radialSegmentCount = 24
            cap.firstMaterial = tube
            let capNode = SCNNode(geometry: cap)
            capNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            capNode.position = SCNVector3(side * 0.0128, 0.0015, 0)
            tonearmPivot.addChildNode(capNode)
        }

        let axle = SCNCylinder(radius: 0.0026, height: 0.0210)
        axle.radialSegmentCount = 20
        axle.firstMaterial = tube
        let axleNode = SCNNode(geometry: axle)
        axleNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        axleNode.position = SCNVector3(0, 0.0015, 0)
        tonearmPivot.addChildNode(axleNode)

        // The arm proper hangs off the horizontal bearing, so cueing it up
        // rotates this node rather than moving parts individually.
        tonearmLift.position = SCNVector3(0, 0.0015, 0)
        tonearmPivot.addChildNode(tonearmLift)

        addArmTube(to: tonearmLift, tube: tube, dark: dark, housing: housing)
        addArmRest(base: base, tube: tube, dark: dark, housing: housing)
        addAntiSkate(base: base, tube: tube, housing: housing)
        addCueingLever(base: base, tube: tube, dark: dark)
    }

    /// Tube, headshell and counterweight: everything that lifts when you cue.
    private func addArmTube(to lift: SCNNode, tube: SCNMaterial,
                            dark: SCNMaterial, housing: SCNMaterial) {
        // A collar where the tube meets the bearing, so it does not simply
        // vanish into the gimbal.
        let shoulder = SCNCylinder(radius: 0.0062, height: 0.0125)
        shoulder.radialSegmentCount = 24
        shoulder.firstMaterial = housing
        let shoulderNode = SCNNode(geometry: shoulder)
        shoulderNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        shoulderNode.position = SCNVector3(0, -0.0045, -0.0088)
        lift.addChildNode(shoulderNode)

        // The tube tapers, as real arms do, and is modelled down -Z so the
        // yaw solver in DeckMetrics stays readable. It stops short of the
        // stylus to leave room for the connector and headshell.
        let tubeLength: CGFloat = 0.197
        let arm = SCNCone(topRadius: 0.0028, bottomRadius: 0.0046, height: tubeLength)
        arm.radialSegmentCount = 32
        arm.firstMaterial = tube
        let armNode = SCNNode(geometry: arm)
        armNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        armNode.position = SCNVector3(0, -0.0045, -tubeLength / 2)
        armNode.castsShadow = true
        lift.addChildNode(armNode)

        // Bayonet collar. A headshell does not grow out of the tube; it locks
        // onto a connector at the end of it, and without that piece the two
        // parts simply float near each other.
        let collar = SCNCylinder(radius: 0.0066, height: 0.0170)
        collar.radialSegmentCount = 28
        collar.firstMaterial = housing
        let collarNode = SCNNode(geometry: collar)
        collarNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        collarNode.position = SCNVector3(0, -0.0052, -0.2045)
        lift.addChildNode(collarNode)

        let lockRing = SCNTorus(ringRadius: 0.0070, pipeRadius: 0.0014)
        lockRing.ringSegmentCount = 28
        lockRing.pipeSegmentCount = 10
        lockRing.firstMaterial = tube
        let lockNode = SCNNode(geometry: lockRing)
        lockNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        lockNode.position = SCNVector3(0, -0.0050, -0.1975)
        lift.addChildNode(lockNode)

        // Headshell plate, sloping down from the collar to the cartridge. Its
        // rear overlaps the collar and its front overlaps the cartridge, so
        // the chain from tube to stylus is continuous.
        let tilt: CGFloat = -0.14
        let headshell = SCNBox(width: 0.0190, height: 0.0050, length: 0.0300,
                               chamferRadius: 0.0014)
        headshell.firstMaterial = tube
        let headNode = SCNNode(geometry: headshell)
        headNode.position = SCNVector3(0, -0.0148, -0.2210)
        headNode.eulerAngles = SCNVector3(tilt, 0, 0)
        lift.addChildNode(headNode)

        let lever = SCNCapsule(capRadius: 0.0013, height: 0.0140)
        lever.firstMaterial = tube
        let leverNode = SCNNode(geometry: lever)
        leverNode.position = SCNVector3(0.0098, -0.0120, -0.2125)
        leverNode.eulerAngles = SCNVector3(0.28, 0, 0.55)
        lift.addChildNode(leverNode)

        let cartridge = SCNBox(width: 0.0134, height: 0.0094, length: 0.0184,
                               chamferRadius: 0.0014)
        cartridge.firstMaterial = Materials.plastic(RGB(0.145, 0.032, 0.034),
                                                    gloss: 0.72, seed: 91)
        let cartridgeNode = SCNNode(geometry: cartridge)
        cartridgeNode.position = SCNVector3(0, -0.0220, -0.2290)
        cartridgeNode.eulerAngles = SCNVector3(tilt, 0, 0)
        lift.addChildNode(cartridgeNode)

        // The stylus has to actually touch the record. Its tip sits on the
        // playing surface, and the position follows from the arm length
        // rather than being eyeballed: it used to hover 2.6 mm clear.
        let stylus = SCNCone(topRadius: 0.0010, bottomRadius: 0.00008, height: 0.0062)
        stylus.firstMaterial = tube
        let stylusNode = SCNNode(geometry: stylus)
        stylusNode.position = SCNVector3(0, DeckMetrics.stylusHeightInArm,
                                         -DeckMetrics.stylusReachInArm)
        lift.addChildNode(stylusNode)

        // Counterweight, with chamfered ends and a scale band, rather than a
        // bare cylinder with a ring floating around it.
        let stub = SCNCylinder(radius: 0.0036, height: 0.0520)
        stub.radialSegmentCount = 18
        stub.firstMaterial = tube
        let stubNode = SCNNode(geometry: stub)
        stubNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        stubNode.position = SCNVector3(0, 0, 0.0260)
        lift.addChildNode(stubNode)

        let weight = SCNCylinder(radius: 0.0176, height: 0.0218)
        weight.radialSegmentCount = 48
        weight.firstMaterial = dark
        let weightNode = SCNNode(geometry: weight)
        weightNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        weightNode.position = SCNVector3(0, 0, 0.0470)
        weightNode.castsShadow = true
        lift.addChildNode(weightNode)

        for offset in [-0.0106, 0.0106] as [CGFloat] {
            let chamfer = SCNTorus(ringRadius: 0.0168, pipeRadius: 0.0016)
            chamfer.ringSegmentCount = 48
            chamfer.pipeSegmentCount = 12
            chamfer.firstMaterial = dark
            let chamferNode = SCNNode(geometry: chamfer)
            chamferNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            chamferNode.position = SCNVector3(0, 0, 0.0470 + offset)
            lift.addChildNode(chamferNode)
        }

        // Tracking-force scale: a bright band set into the weight.
        let scale = SCNCylinder(radius: 0.0178, height: 0.0042)
        scale.radialSegmentCount = 48
        scale.firstMaterial = tube
        let scaleNode = SCNNode(geometry: scale)
        scaleNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        scaleNode.position = SCNVector3(0, 0, 0.0384)
        lift.addChildNode(scaleNode)
    }

    /// A cradle the arm actually sits in, plus its clip.
    private func addArmRest(base: CGFloat, tube: SCNMaterial,
                            dark: SCNMaterial, housing: SCNMaterial) {
        let rest = DeckMetrics.armRestPosition
        let x = rest.x
        let z = rest.y

        let plate = SCNCylinder(radius: 0.0108, height: 0.0035)
        plate.radialSegmentCount = 32
        plate.firstMaterial = tube
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(x, base + 0.0018, z)
        node.addChildNode(plateNode)

        let stem = SCNCylinder(radius: 0.0044, height: 0.0245)
        stem.radialSegmentCount = 20
        stem.firstMaterial = housing
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(x, base + 0.0158, z)
        node.addChildNode(stemNode)

        // Two uprights with a gap: the arm drops between them, which is what
        // makes it read as a rest rather than a block on a stick.
        for side in [-1.0, 1.0] as [CGFloat] {
            let jaw = SCNBox(width: 0.0032, height: 0.0120, length: 0.0105,
                             chamferRadius: 0.0014)
            jaw.firstMaterial = dark
            let jawNode = SCNNode(geometry: jaw)
            jawNode.position = SCNVector3(x + side * 0.0052, base + 0.0335, z)
            jawNode.eulerAngles = SCNVector3(0, 0, side * 0.16)
            node.addChildNode(jawNode)
        }

        let cradle = SCNBox(width: 0.0138, height: 0.0030, length: 0.0105,
                            chamferRadius: 0.0012)
        cradle.firstMaterial = dark
        let cradleNode = SCNNode(geometry: cradle)
        cradleNode.position = SCNVector3(x, base + 0.0288, z)
        node.addChildNode(cradleNode)
    }

    /// Anti-skate: a weighted dial with a slot, not a bare stub.
    private func addAntiSkate(base: CGFloat, tube: SCNMaterial, housing: SCNMaterial) {
        let x = DeckMetrics.pivot.x + 0.0315
        let z = DeckMetrics.pivot.y + 0.0135

        let stem = SCNCylinder(radius: 0.0042, height: 0.0135)
        stem.radialSegmentCount = 20
        stem.firstMaterial = housing
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(x, base + 0.0068, z)
        node.addChildNode(stemNode)

        let dial = SCNCylinder(radius: 0.0092, height: 0.0048)
        dial.radialSegmentCount = 36
        dial.firstMaterial = tube
        let dialNode = SCNNode(geometry: dial)
        dialNode.position = SCNVector3(x, base + 0.0159, z)
        node.addChildNode(dialNode)

        let slot = SCNBox(width: 0.0014, height: 0.0008, length: 0.0062, chamferRadius: 0)
        slot.firstMaterial = Materials.plastic(RGB(0.05, 0.05, 0.05), gloss: 0.2)
        let slotNode = SCNNode(geometry: slot)
        slotNode.position = SCNVector3(x, base + 0.0182, z + 0.0012)
        node.addChildNode(slotNode)
    }

    /// The lever you push to lower the arm, attached to a base plate so it is
    /// visibly bolted to the deck.
    private func addCueingLever(base: CGFloat, tube: SCNMaterial, dark: SCNMaterial) {
        let x = DeckMetrics.pivot.x - 0.0305
        let z = DeckMetrics.pivot.y + 0.0265

        let plate = SCNBox(width: 0.0180, height: 0.0032, length: 0.0235,
                           chamferRadius: 0.0014)
        plate.firstMaterial = tube
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(x, base + 0.0016, z + 0.0055)
        node.addChildNode(plateNode)

        let pivotPost = SCNCylinder(radius: 0.0048, height: 0.0125)
        pivotPost.radialSegmentCount = 20
        pivotPost.firstMaterial = tube
        let pivotNode = SCNNode(geometry: pivotPost)
        pivotNode.position = SCNVector3(x, base + 0.0094, z)
        node.addChildNode(pivotNode)

        // A capsule, so the end you push is rounded rather than a cut box.
        let paddle = SCNCapsule(capRadius: 0.0030, height: 0.0265)
        paddle.firstMaterial = dark
        let paddleNode = SCNNode(geometry: paddle)
        paddleNode.position = SCNVector3(x, base + 0.0172, z + 0.0092)
        paddleNode.eulerAngles = SCNVector3(CGFloat.pi / 2 - 0.26, 0, 0)
        node.addChildNode(paddleNode)
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
        knobNode.position = SCNVector3(0.168, base + 0.0058, 0.138)
        knobNode.castsShadow = true
        node.addChildNode(knobNode)

        let knurl = SCNTorus(ringRadius: 0.0168, pipeRadius: 0.0018)
        knurl.ringSegmentCount = 48
        knurl.firstMaterial = Materials.machinedMetal(tint: preset.metal.scaled(0.8),
                                                      roughness: 0.34)
        let knurlNode = SCNNode(geometry: knurl)
        knurlNode.position = SCNVector3(0.168, base + 0.0058, 0.138)
        node.addChildNode(knurlNode)

        let mark = SCNBox(width: 0.0016, height: 0.0006, length: 0.0075, chamferRadius: 0)
        mark.firstMaterial = Materials.plastic(RGB(0.06, 0.06, 0.06), gloss: 0.2)
        let markNode = SCNNode(geometry: mark)
        markNode.position = SCNVector3(0.168, base + 0.0118, 0.1475)
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
