import AppKit
import SceneKit

/// Everything on the desk that is not the turntable.
///
/// A deck alone on a clean surface reads as a product shot. The mug, the
/// plant, the books someone stacked badly — that is what makes it a room
/// somebody uses. All of it is built from primitives and procedural artwork,
/// so the repository still carries no assets.
struct Props {

    let preset: ScenePreset
    var pressing: Pressing = .black

    // MARK: Record sleeve

    struct Sleeve {
        let node: SCNNode
        /// Exposed so the cover can be swapped when the track changes.
        let material: SCNMaterial
    }

    /// A 12-inch sleeve leaning against the wall, with its record peeking out.
    func sleeve(artwork: NSImage) -> Sleeve {
        let node = SCNNode()
        let material = Materials.paperboard(artwork, seed: 2121)
        let card = Materials.paperboard(Textures.solid(RGB(0.72, 0.70, 0.66)), seed: 2122)

        let board = SCNBox(width: 0.315, height: 0.315, length: 0.0055, chamferRadius: 0.0012)
        // SCNBox face order: front, right, back, left, top, bottom.
        board.materials = [material, card, card, card, card, card]
        let boardNode = SCNNode(geometry: board)
        boardNode.castsShadow = true
        node.addChildNode(boardNode)

        // The record itself, slid part way out of the open edge.
        let inner = SCNCylinder(radius: 0.1495, height: 0.0016)
        inner.radialSegmentCount = 80
        let vinyl = Materials.vinyl(pressing)
        inner.materials = [Materials.vinylEdge(pressing), vinyl, vinyl]
        let innerNode = SCNNode(geometry: inner)
        innerNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        innerNode.position = SCNVector3(0.055, 0.012, -0.005)
        node.addChildNode(innerNode)

        return Sleeve(node: node, material: material)
    }

    /// A sleeve standing in a shallow wooden cradle.
    ///
    /// A record propped straight against a wall always looks like it is about
    /// to slide. A stand gives it a reason to be upright, and the lip casts a
    /// line of shadow across the bottom of the cover.
    func sleeveStand(artwork: NSImage) -> Sleeve {
        let node = SCNNode()
        let timber = Materials.varnishedWood(base: preset.deskBase.scaled(1.35),
                                             grain: preset.deskGrain.scaled(1.35),
                                             seed: 61)

        let plank = SCNBox(width: 0.368, height: 0.0165, length: 0.088,
                           chamferRadius: 0.0022)
        plank.firstMaterial = timber
        let plankNode = SCNNode(geometry: plank)
        plankNode.position = SCNVector3(0, 0.00825, 0)
        plankNode.castsShadow = true
        node.addChildNode(plankNode)

        // The lip the cover rests against, and a lower rail behind it so the
        // sleeve sits in a groove rather than on a flat board.
        let lip = SCNBox(width: 0.368, height: 0.0165, length: 0.0085,
                         chamferRadius: 0.0016)
        lip.firstMaterial = timber
        let lipNode = SCNNode(geometry: lip)
        lipNode.position = SCNVector3(0, 0.0248, 0.0340)
        node.addChildNode(lipNode)

        let rail = SCNBox(width: 0.368, height: 0.0105, length: 0.0075,
                          chamferRadius: 0.0014)
        rail.firstMaterial = timber
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3(0, 0.0218, -0.0230)
        node.addChildNode(railNode)

        // The sleeve, reclined into the cradle.
        let sleeve = self.sleeve(artwork: artwork)
        sleeve.node.position = SCNVector3(0, 0.1740, 0.0045)
        sleeve.node.eulerAngles = SCNVector3(-0.115, 0, 0)
        node.addChildNode(sleeve.node)

        return Sleeve(node: node, material: sleeve.material)
    }

    /// A framed print standing on the desk, leaning back against the wall.
    ///
    /// Hung on the wall it would sit above the top of the frame on a 16:9
    /// crop. Leaning it on the desk keeps it in shot, and is how prints
    /// actually end up in a room like this.
    func leaningFrame() -> SCNNode {
        let frame = SCNNode()
        let width: CGFloat = 0.255, height: CGFloat = 0.330, depth: CGFloat = 0.019

        let moulding = SCNBox(width: width, height: height, length: depth,
                              chamferRadius: 0.0022)
        moulding.firstMaterial = Materials.varnishedWood(base: RGB(0.215, 0.145, 0.088),
                                                         grain: RGB(0.330, 0.228, 0.140),
                                                         seed: 83)
        let mouldingNode = SCNNode(geometry: moulding)
        mouldingNode.castsShadow = true
        frame.addChildNode(mouldingNode)

        // Mount board and print, each stepped forward so the frame has depth.
        let mount = SCNBox(width: width - 0.030, height: height - 0.030,
                           length: 0.002, chamferRadius: 0)
        mount.firstMaterial = Materials.paperboard(Textures.solid(RGB(0.925, 0.915, 0.895)),
                                                   seed: 84)
        let mountNode = SCNNode(geometry: mount)
        mountNode.position = SCNVector3(0, 0, depth / 2 + 0.001)
        frame.addChildNode(mountNode)

        let print = SCNBox(width: width - 0.088, height: height - 0.112,
                           length: 0.001, chamferRadius: 0)
        print.firstMaterial = Materials.paperboard(
            GenerativeCover.make(seed: "gallery-print", size: 512).image, seed: 85)
        let printNode = SCNNode(geometry: print)
        printNode.position = SCNVector3(0, 0.009, depth / 2 + 0.003)
        frame.addChildNode(printNode)

        // Standing on the desk, tipped back onto the wall.
        frame.position = SCNVector3(0, height / 2 + 0.002, 0)
        frame.eulerAngles = SCNVector3(-0.135, 0, 0)
        let holder = SCNNode()
        holder.addChildNode(frame)
        return holder
    }

    // MARK: Record stack

    /// Four sleeves dropped on the desk, each a little out of square.
    struct RecordStack {
        let node: SCNNode
        /// The face of the top sleeve, the only one the fan leaves visible.
        let topCover: SCNMaterial
    }

    func recordStack() -> RecordStack {
        let stack = SCNNode()
        // A 12-inch record is 1.9 mm and its sleeve is card, so a filled
        // sleeve is about 5 mm. Anything more and the pile reads as plywood.
        let thickness: CGFloat = 0.0032
        let topCover = Materials.paperboard(
            GenerativeCover.make(seed: "stack").image, seed: 711)

        for i in 0..<4 {
            let sleeve = SCNBox(width: 0.315, height: thickness, length: 0.315,
                                chamferRadius: 0.0005)
            let card = Materials.paperboard(
                Textures.solid(RGB(0.055 + CGFloat(i) * 0.02,
                                   0.052 + CGFloat(i) * 0.02,
                                   0.058 + CGFloat(i) * 0.02)),
                seed: UInt64(700 + i))
            // SCNBox face order: front, right, back, left, top, bottom.
            if i == 3 {
                sleeve.materials = [card, card, card, card, topCover, card]
            } else {
                sleeve.materials = [card]
            }
            let node = SCNNode(geometry: sleeve)
            node.position = SCNVector3(CGFloat(i) * 0.005,
                                       thickness / 2 + CGFloat(i) * thickness,
                                       CGFloat(i) * -0.004)
            node.eulerAngles = SCNVector3(0, CGFloat(i) * 0.030, 0)
            node.castsShadow = true
            stack.addChildNode(node)
        }
        return RecordStack(node: stack, topCover: topCover)
    }

    // MARK: Mug

    /// Glazed ceramic, with coffee in it. The handle is a torus clipped by
    /// being half-buried in the body, which is cheaper than a real sweep and
    /// indistinguishable at this size.
    func mug() -> SCNNode {
        let mug = SCNNode()
        let glaze = Materials.ceramic(RGB(0.60, 0.575, 0.535))

        let body = SCNTube(innerRadius: 0.0375, outerRadius: 0.042, height: 0.094)
        body.radialSegmentCount = 48
        body.materials = [glaze, glaze, glaze, glaze, glaze]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.047, 0)
        bodyNode.castsShadow = true
        mug.addChildNode(bodyNode)

        let base = SCNCylinder(radius: 0.042, height: 0.006)
        base.radialSegmentCount = 48
        base.firstMaterial = glaze
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.003, 0)
        mug.addChildNode(baseNode)

        let handle = SCNTorus(ringRadius: 0.026, pipeRadius: 0.0062)
        handle.ringSegmentCount = 40
        handle.pipeSegmentCount = 16
        handle.firstMaterial = glaze
        let handleNode = SCNNode(geometry: handle)
        handleNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        handleNode.position = SCNVector3(0.058, 0.052, 0)
        mug.addChildNode(handleNode)

        // Coffee: dark, and glossy enough to hold a reflection of the window.
        let coffee = SCNCylinder(radius: 0.0372, height: 0.002)
        coffee.radialSegmentCount = 48
        let liquid = SCNMaterial()
        liquid.lightingModel = .physicallyBased
        liquid.diffuse.contents = Textures.solid(RGB(0.055, 0.030, 0.018))
        liquid.roughness.contents = 0.06
        liquid.metalness.contents = 0.0
        coffee.materials = [liquid, liquid, liquid]
        let coffeeNode = SCNNode(geometry: coffee)
        coffeeNode.position = SCNVector3(0, 0.079, 0)
        mug.addChildNode(coffeeNode)

        return mug
    }

    // MARK: Plant

    /// A potted trailing plant. Leaves are flattened spheres on bent stems —
    /// enough silhouette to read as foliage once it is thrown out of focus.
    func plant() -> SCNNode {
        let plant = SCNNode()

        let pot = SCNCone(topRadius: 0.072, bottomRadius: 0.056, height: 0.105)
        pot.radialSegmentCount = 36
        pot.firstMaterial = Materials.ceramic(RGB(0.52, 0.34, 0.26))
        let potNode = SCNNode(geometry: pot)
        potNode.position = SCNVector3(0, 0.0525, 0)
        potNode.castsShadow = true
        plant.addChildNode(potNode)

        let rim = SCNTorus(ringRadius: 0.072, pipeRadius: 0.0055)
        rim.firstMaterial = Materials.ceramic(RGB(0.56, 0.37, 0.28))
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, 0.104, 0)
        plant.addChildNode(rimNode)

        let soil = SCNCylinder(radius: 0.068, height: 0.006)
        soil.firstMaterial = Materials.rubber(RGB(0.085, 0.060, 0.042), seed: 310)
        let soilNode = SCNNode(geometry: soil)
        soilNode.position = SCNVector3(0, 0.100, 0)
        plant.addChildNode(soilNode)

        // Deterministic placement: the plant should look the same every launch.
        var rng = GenerativeCover.SplitMix(seed: 90210)

        // Several greens rather than one: a single leaf colour is what makes
        // CG foliage read as plastic.
        let greens = [
            Materials.leaf(RGB(0.205, 0.390, 0.185), seed: 920),
            Materials.leaf(RGB(0.265, 0.455, 0.225), seed: 921),
            Materials.leaf(RGB(0.150, 0.300, 0.150), seed: 922),
            Materials.leaf(RGB(0.310, 0.480, 0.250), seed: 923),
        ]
        let stemMaterial = Materials.leaf(RGB(0.22, 0.31, 0.16), seed: 911)

        for i in 0..<22 {
            // Spread by the golden angle, which is how a real plant fills a pot.
            let angle = CGFloat(i) * 2.3998 + rng.unit() * 0.22
            // Outer leaves trail further and hang lower than the crown.
            let maturity = rng.unit()
            let lean = 0.30 + maturity * 1.00
            let length = 0.095 + rng.unit() * 0.095
            let height = 0.055 + (1 - maturity) * 0.145

            let stem = SCNCylinder(radius: 0.0019, height: height)
            stem.radialSegmentCount = 8
            stem.firstMaterial = stemMaterial
            let stemNode = SCNNode(geometry: stem)
            stemNode.position = SCNVector3(
                sin(angle) * lean * height * 0.32,
                0.10 + height / 2,
                cos(angle) * lean * height * 0.32)
            stemNode.eulerAngles = SCNVector3(lean * 0.55 * cos(angle), 0,
                                              -lean * 0.55 * sin(angle))
            plant.addChildNode(stemNode)

            let reach = 0.022 + lean * height * 0.78
            let leaf = SCNSphere(radius: length / 2)
            leaf.segmentCount = 20
            leaf.firstMaterial = greens[i % greens.count]
            let leafNode = SCNNode(geometry: leaf)
            // Flattened into a blade, and tapered so it is not a lozenge.
            leafNode.scale = SCNVector3(0.46 + rng.unit() * 0.16, 0.085, 1.0)
            leafNode.position = SCNVector3(
                sin(angle) * reach,
                0.10 + height * (0.90 - lean * 0.22),
                cos(angle) * reach)
            leafNode.eulerAngles = SCNVector3(
                -0.35 + rng.unit() * 0.5 - lean * 0.30,
                angle,
                rng.unit() * 0.7 - 0.35)
            leafNode.castsShadow = true
            plant.addChildNode(leafNode)
        }
        return plant
    }

    // MARK: Books

    /// A short stack, squared up badly, with one laid across the top.
    func books() -> SCNNode {
        let stack = SCNNode()
        let spines: [RGB] = [RGB(0.34, 0.16, 0.13), RGB(0.16, 0.20, 0.26),
                             RGB(0.52, 0.44, 0.30), RGB(0.20, 0.25, 0.19)]
        var y: CGFloat = 0
        for (i, colour) in spines.enumerated() {
            let height: CGFloat = 0.022 + CGFloat(i % 2) * 0.008
            let book = SCNBox(width: 0.155, height: height, length: 0.215,
                              chamferRadius: 0.0018)
            let cover = Materials.paperboard(Textures.solid(colour), seed: UInt64(500 + i))
            let pages = Materials.paperboard(Textures.solid(RGB(0.84, 0.81, 0.74)),
                                             seed: UInt64(520 + i))
            book.materials = [cover, pages, cover, pages, cover, cover]
            let node = SCNNode(geometry: book)
            node.position = SCNVector3(CGFloat(i % 2) * 0.009 - 0.004, y + height / 2, 0)
            node.eulerAngles = SCNVector3(0, CGFloat(i) * 0.045 - 0.06, 0)
            node.castsShadow = true
            stack.addChildNode(node)
            y += height
        }
        return stack
    }

    // MARK: Headphones

    /// Over-ears resting on their side, the way they actually get put down.
    func headphones() -> SCNNode {
        let cans = SCNNode()
        let leather = Materials.rubber(RGB(0.055, 0.053, 0.056), seed: 620)
        let shell = Materials.plastic(RGB(0.085, 0.083, 0.088), gloss: 0.3, seed: 621)

        // Headband: half a torus, laid on its side.
        let band = SCNTorus(ringRadius: 0.078, pipeRadius: 0.0085)
        band.ringSegmentCount = 44
        band.firstMaterial = leather
        let bandNode = SCNNode(geometry: band)
        bandNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        bandNode.position = SCNVector3(0, 0.080, 0)
        bandNode.castsShadow = true
        cans.addChildNode(bandNode)

        for side in [-1.0, 1.0] as [CGFloat] {
            let cup = SCNCylinder(radius: 0.040, height: 0.028)
            cup.radialSegmentCount = 36
            cup.materials = [shell, shell, shell]
            let cupNode = SCNNode(geometry: cup)
            cupNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            cupNode.position = SCNVector3(side * 0.072, 0.042, 0)
            cupNode.castsShadow = true
            cans.addChildNode(cupNode)

            let pad = SCNTorus(ringRadius: 0.032, pipeRadius: 0.011)
            pad.firstMaterial = leather
            let padNode = SCNNode(geometry: pad)
            padNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            padNode.position = SCNVector3(side * 0.058, 0.042, 0)
            cans.addChildNode(padNode)
        }
        return cans
    }

    // MARK: Lamp

    /// Brass stem, fluted shade, warm bulb. In Lamplight this is the thing
    /// the key light is pretending to be, so it has to be where the light is.
    func lamp() -> SCNNode {
        let lamp = SCNNode()
        let brass = Materials.machinedMetal(tint: preset.metal, roughness: 0.26)

        let base = SCNCylinder(radius: 0.058, height: 0.011)
        base.radialSegmentCount = 44
        base.firstMaterial = brass
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.0055, 0)
        baseNode.castsShadow = true
        lamp.addChildNode(baseNode)

        let collar = SCNTorus(ringRadius: 0.052, pipeRadius: 0.0055)
        collar.firstMaterial = brass
        let collarNode = SCNNode(geometry: collar)
        collarNode.position = SCNVector3(0, 0.012, 0)
        lamp.addChildNode(collarNode)

        let stem = SCNCylinder(radius: 0.0075, height: 0.115)
        stem.radialSegmentCount = 20
        stem.firstMaterial = brass
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, 0.070, 0)
        lamp.addChildNode(stemNode)

        // Bulb inside the shade, so the shade is lit from within.
        let bulb = SCNSphere(radius: 0.015)
        bulb.firstMaterial = Materials.emissive(RGB(1.0, 0.86, 0.62), intensity: 2.2)
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.position = SCNVector3(0, 0.168, 0)
        bulbNode.castsShadow = false
        lamp.addChildNode(bulbNode)

        let shade = SCNCone(topRadius: 0.046, bottomRadius: 0.072, height: 0.112)
        shade.radialSegmentCount = 44
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = Textures.solid(RGB(1.0, 0.88, 0.70))
        glass.emission.contents = Textures.solid(RGB(1.0, 0.80, 0.55))
        glass.emission.intensity = 0.55
        glass.roughness.contents = 0.42
        glass.metalness.contents = 0.0
        glass.transparency = 0.94
        glass.isDoubleSided = true
        shade.materials = [glass, glass, glass]
        let shadeNode = SCNNode(geometry: shade)
        shadeNode.position = SCNVector3(0, 0.172, 0)
        shadeNode.castsShadow = false
        lamp.addChildNode(shadeNode)

        return lamp
    }

    // MARK: Wall

    /// A framed print. The art is generated, like every other image here.
    func framedArt() -> SCNNode {
        let frame = SCNNode()
        let width: CGFloat = 0.46, height: CGFloat = 0.60, depth: CGFloat = 0.022

        let outer = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.002)
        outer.firstMaterial = Materials.varnishedWood(base: RGB(0.21, 0.14, 0.085),
                                                      grain: RGB(0.33, 0.22, 0.13),
                                                      seed: 77)
        let outerNode = SCNNode(geometry: outer)
        outerNode.castsShadow = true
        frame.addChildNode(outerNode)

        // Mount board, then the print, each stepped forward.
        let mount = SCNBox(width: width - 0.042, height: height - 0.042,
                           length: 0.002, chamferRadius: 0)
        mount.firstMaterial = Materials.paperboard(Textures.solid(RGB(0.88, 0.86, 0.81)),
                                                   seed: 78)
        let mountNode = SCNNode(geometry: mount)
        mountNode.position = SCNVector3(0, 0, depth / 2 + 0.001)
        frame.addChildNode(mountNode)

        let print = SCNBox(width: width - 0.13, height: height - 0.17,
                           length: 0.001, chamferRadius: 0)
        print.firstMaterial = Materials.paperboard(
            GenerativeCover.make(seed: "wall-print", size: 512).image, seed: 79)
        let printNode = SCNNode(geometry: print)
        printNode.position = SCNVector3(0, 0.012, depth / 2 + 0.003)
        frame.addChildNode(printNode)

        return frame
    }

    /// A wall shelf with records filed upright, slightly fanned.
    func shelf() -> SCNNode {
        let shelf = SCNNode()
        let timber = Materials.varnishedWood(base: preset.deskBase.scaled(1.15),
                                             grain: preset.deskGrain.scaled(1.15),
                                             seed: 23)

        let board = SCNBox(width: 0.70, height: 0.026, length: 0.185, chamferRadius: 0.002)
        board.firstMaterial = timber
        let boardNode = SCNNode(geometry: board)
        boardNode.castsShadow = true
        shelf.addChildNode(boardNode)

        for (i, bracketX) in [-0.28, 0.28].enumerated() {
            let bracket = SCNBox(width: 0.016, height: 0.085, length: 0.090,
                                 chamferRadius: 0.002)
            bracket.firstMaterial = Materials.machinedMetal(tint: RGB(0.16, 0.16, 0.17),
                                                            roughness: 0.5,
                                                            seed: UInt64(300 + i))
            let node = SCNNode(geometry: bracket)
            node.position = SCNVector3(CGFloat(bracketX), -0.055, -0.04)
            shelf.addChildNode(node)
        }

        // Filed records, leaning as a part-full shelf always does.
        var rng = GenerativeCover.SplitMix(seed: 5150)
        for i in 0..<9 {
            let sleeve = SCNBox(width: 0.006, height: 0.315, length: 0.315,
                                chamferRadius: 0.001)
            let tone = 0.07 + rng.unit() * 0.22
            let card = Materials.paperboard(
                Textures.solid(RGB(tone, tone * 0.96, tone * 0.92)),
                seed: UInt64(800 + i))
            sleeve.materials = [card]
            let node = SCNNode(geometry: sleeve)
            node.position = SCNVector3(-0.30 + CGFloat(i) * 0.0075,
                                       0.013 + 0.315 / 2 - 0.004,
                                       -0.012)
            node.eulerAngles = SCNVector3(0, 0, -0.05 - rng.unit() * 0.06)
            node.castsShadow = true
            shelf.addChildNode(node)
        }
        return shelf
    }
}
