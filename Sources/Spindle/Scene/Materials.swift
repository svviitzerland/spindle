import AppKit
import SceneKit

/// The material library.
///
/// The single biggest difference between a render that reads as a photograph
/// and one that reads as a toy is surface imperfection. Nothing in a real room
/// has a uniform roughness: paint has orange peel, metal has brushing and
/// fingerprints, lacquer has fine scratches, wood has varnish that pools.
/// Every material here therefore carries a roughness map and a normal map —
/// never a flat scalar.
///
/// Maps are generated once and cached, because several of them are evaluated
/// per pixel and the scene rebuilds whenever the mood changes.
enum Materials {

    // MARK: Cache

    private static var cache: [String: CGImage] = [:]

    private static func cached(_ key: String, _ build: () -> CGImage) -> CGImage {
        if let hit = cache[key] { return hit }
        let image = build()
        cache[key] = image
        return image
    }

    /// Drop generated maps when the app is idle; they rebuild on demand.
    static func flushCache() { cache.removeAll() }

    // MARK: Building blocks

    private static func pbr(_ configure: (SCNMaterial) -> Void) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.isDoubleSided = false
        configure(material)
        // Fine maps alias badly at a distance without mips and anisotropy, and
        // aliasing is what makes a render look computer-generated.
        for property in [material.diffuse, material.roughness, material.normal,
                         material.metalness, material.ambientOcclusion] {
            property.mipFilter = .linear
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            property.maxAnisotropy = 16
        }
        return material
    }

    // MARK: Wood

    /// Desk timber under a satin varnish. The clear coat is what sells it:
    /// bare diffuse wood looks like cardboard.
    static func varnishedWood(base: RGB, grain: RGB, seed: UInt64 = 7) -> SCNMaterial {
        let key = "wood-\(base)-\(grain)-\(seed)"
        let diffuse = cached(key + "-d") { Textures.wood(base: base, grain: grain, seed: seed) }
        let roughness = cached(key + "-r") { Textures.woodRoughness(seed: seed) }
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed &+ 91)
            return Textures.normalMap(size: 512, strength: 0.5) { u, v in
                // Grain sits slightly proud of the varnish, plus the faint
                // ripple a brushed finish leaves behind.
                let pore = noise.value(v * 520.0, u * 9.0)
                let ripple = noise.fbm(u * 26.0, v * 26.0, octaves: 3)
                return (pore > 0.80 ? -0.5 : 0) + ripple * 0.25
            }
        }
        return pbr { m in
            m.diffuse.contents = diffuse
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.6
            m.metalness.contents = 0.0
            m.clearCoat.contents = 0.45
            m.clearCoatRoughness.contents = 0.14
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.roughness.wrapS = .repeat
            m.roughness.wrapT = .repeat
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
        }
    }

    // MARK: Paint and plastics

    /// The plinth. Matte furniture paint: orange peel in the normal, and
    /// roughness that drifts so highlights break up instead of reading as one
    /// flat sheet.
    static func mattePaint(_ color: RGB, seed: UInt64 = 31, wear: Double = 1.0) -> SCNMaterial {
        let key = "paint-\(color)-\(seed)-\(wear)"
        let roughness = cached(key + "-r") {
            let noise = Textures.Noise(seed: seed)
            return Textures.grayscale(size: 512) { u, v in
                0.44 + noise.fbm(u * 7.0, v * 7.0, octaves: 4) * 0.16
                     + noise.value(u * 190.0, v * 190.0) * 0.05
            }
        }
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed &+ 5)
            return Textures.normalMap(size: 512, strength: 0.28) { u, v in
                // Orange peel: the slight pebbling sprayed paint always has.
                noise.fbm(u * 58.0, v * 58.0, octaves: 3) * 0.8
                    + noise.value(u * 300.0, v * 300.0) * 0.2
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(color)
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.35 * wear
            m.metalness.contents = 0.0
            m.clearCoat.contents = 0.18
            m.clearCoatRoughness.contents = 0.3
        }
    }

    /// Moulded plastic for knobs, feet and the tonearm's dark parts.
    static func plastic(_ color: RGB, gloss: Double = 0.35, seed: UInt64 = 77) -> SCNMaterial {
        let key = "plastic-\(color)-\(gloss)-\(seed)"
        let roughness = cached(key + "-r") {
            let noise = Textures.Noise(seed: seed)
            return Textures.grayscale(size: 256) { u, v in
                (1.0 - gloss) * (0.85 + noise.fbm(u * 14.0, v * 14.0, octaves: 3) * 0.3)
            }
        }
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed &+ 3)
            return Textures.normalMap(size: 256, strength: 0.22) { u, v in
                noise.value(u * 220.0, v * 220.0)
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(color)
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.4
            m.metalness.contents = 0.0
        }
    }

    /// Rubber: the feet, the drive belt, the cable jacket.
    static func rubber(_ color: RGB, seed: UInt64 = 123) -> SCNMaterial {
        let key = "rubber-\(color)-\(seed)"
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed)
            return Textures.normalMap(size: 256, strength: 0.6) { u, v in
                noise.fbm(u * 90.0, v * 90.0, octaves: 3)
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(color)
            m.roughness.contents = 0.88
            m.normal.contents = normal
            m.normal.intensity = 0.7
            m.metalness.contents = 0.0
        }
    }

    // MARK: Metal

    /// Platter and tonearm tube. Concentric brushing plus the odd fingerprint,
    /// because spotless metal is the most synthetic-looking surface there is.
    static func brushedMetal(tint: RGB, seed: UInt64 = 303, polish: Double = 1.0) -> SCNMaterial {
        let key = "metal-\(tint)-\(seed)-\(polish)"
        let roughness = cached(key + "-r") {
            let noise = Textures.Noise(seed: seed)
            return Textures.grayscale(size: 512) { u, v in
                let dx = u - 0.5, dy = v - 0.5
                let angle = atan2(dy, dx)
                let radius = (dx * dx + dy * dy).squareRoot() * 2
                let brush = noise.value(angle * 260.0 + radius * 4.0) * 0.12
                // Smudges where fingers would actually land: near the rim.
                let smudge = noise.fbm(u * 5.0, v * 5.0, octaves: 3)
                let print = radius > 0.55 ? max(0, smudge - 0.55) * 0.5 : 0
                return (0.17 + brush + print) / max(polish, 0.2)
            }
        }
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed &+ 17)
            return Textures.normalMap(size: 1024, strength: 0.4, tiles: false) { u, v in
                let dx = u - 0.5, dy = v - 0.5
                let angle = atan2(dy, dx)
                let radius = (dx * dx + dy * dy).squareRoot() * 2
                // Lathe marks run around the platter, not across it.
                return noise.value(angle * 520.0 + radius * 6.0) * 0.6
                    + noise.value(radius * 900.0) * 0.4
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(tint)
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.5
            m.metalness.contents = 0.92
        }
    }

    /// Machined parts seen from any angle — screws, the spindle, arm fittings.
    /// Isotropic rather than brushed, so it does not stripe on small geometry.
    static func machinedMetal(tint: RGB, roughness level: Double = 0.22,
                              seed: UInt64 = 404) -> SCNMaterial {
        let key = "machined-\(tint)-\(level)-\(seed)"
        let roughness = cached(key + "-r") {
            let noise = Textures.Noise(seed: seed)
            return Textures.grayscale(size: 256) { u, v in
                level + noise.fbm(u * 24.0, v * 24.0, octaves: 3) * 0.14
            }
        }
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed &+ 9)
            return Textures.normalMap(size: 256, strength: 0.25) { u, v in
                noise.value(u * 420.0, v * 420.0)
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(tint)
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.35
            m.metalness.contents = 0.95
        }
    }

    // MARK: Soft goods

    /// The slip mat. Felt is almost pure diffuse with a deep fibre normal.
    static func felt(_ color: RGB, seed: UInt64 = 555) -> SCNMaterial {
        let key = "felt-\(color)-\(seed)"
        let normal = cached(key + "-n") {
            let noise = Textures.Noise(seed: seed)
            return Textures.normalMap(size: 512, strength: 0.9) { u, v in
                noise.value(u * 300.0, v * 300.0) * 0.7
                    + noise.fbm(u * 40.0, v * 40.0, octaves: 3) * 0.3
            }
        }
        let roughness = cached(key + "-r") {
            let noise = Textures.Noise(seed: seed &+ 2)
            return Textures.grayscale(size: 256) { u, v in
                0.92 + noise.value(u * 120.0, v * 120.0) * 0.06
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(color)
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.85
            m.metalness.contents = 0.0
        }
    }

    /// Printed card, for sleeves and book covers.
    static func paperboard(_ contents: Any, seed: UInt64 = 666) -> SCNMaterial {
        let normal = cached("paper-n-\(seed)") {
            let noise = Textures.Noise(seed: seed)
            return Textures.normalMap(size: 256, strength: 0.3) { u, v in
                noise.fbm(u * 120.0, v * 120.0, octaves: 3)
            }
        }
        let roughness = cached("paper-r-\(seed)") {
            let noise = Textures.Noise(seed: seed &+ 4)
            return Textures.grayscale(size: 256) { u, v in
                0.72 + noise.fbm(u * 18.0, v * 18.0, octaves: 3) * 0.16
            }
        }
        return pbr { m in
            m.diffuse.contents = contents
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 0.3
            m.metalness.contents = 0.0
        }
    }

    // MARK: Vinyl

    /// The record. Grooves in the normal map, plus the fine radial scratching
    /// and dust that every played record carries.
    static func vinyl(_ pressing: Pressing = .black) -> SCNMaterial {
        let key = "vinyl-\(pressing.id)-\(pressing.color)-\(pressing.translucent)"
        let diffuse = cached(key) { Textures.vinylDiffuse(pressing: pressing) }
        let normal = cached("vinyl-n") { Textures.vinylNormal() }
        let roughness = cached("vinyl-r") { Textures.vinylRoughness() }
        return pbr { m in
            m.diffuse.contents = diffuse
            m.roughness.contents = roughness
            m.normal.contents = normal
            m.normal.intensity = 1.0
            m.metalness.contents = 0.0
            // Lacquer over the groove: this is what produces the moving sheen.
            m.clearCoat.contents = 0.9
            m.clearCoatRoughness.contents = 0.06
        }
    }

    /// The rim of the disc, which is seen edge on and so needs no groove map.
    static func vinylEdge(_ pressing: Pressing = .black) -> SCNMaterial {
        plastic(pressing.color.scaled(0.9), gloss: 0.55,
                seed: UInt64(abs(pressing.id.hashValue % 1000)))
    }

    // MARK: Glazed and glass

    static func ceramic(_ color: RGB, seed: UInt64 = 808) -> SCNMaterial {
        let normal = cached("ceramic-n-\(seed)") {
            let noise = Textures.Noise(seed: seed)
            return Textures.normalMap(size: 256, strength: 0.14) { u, v in
                noise.fbm(u * 30.0, v * 30.0, octaves: 3)
            }
        }
        return pbr { m in
            m.diffuse.contents = Textures.solid(color)
            m.roughness.contents = 0.16
            m.normal.contents = normal
            m.normal.intensity = 0.25
            m.metalness.contents = 0.0
            m.clearCoat.contents = 0.9
            m.clearCoatRoughness.contents = 0.05
        }
    }

    /// Glass and acrylic. Thin, so refraction is kept subtle.
    static func glass(tint: RGB = RGB(0.92, 0.94, 0.96), transparency: CGFloat = 0.12) -> SCNMaterial {
        pbr { m in
            m.diffuse.contents = Textures.solid(tint)
            m.roughness.contents = 0.03
            m.metalness.contents = 0.0
            m.transparency = transparency
            m.transparencyMode = .dualLayer
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
        }
    }

    /// Something that emits rather than reflects: a lamp bulb, an indicator.
    static func emissive(_ color: RGB, intensity: CGFloat = 1.0) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Textures.solid(color)
        material.emission.contents = Textures.solid(color)
        material.emission.intensity = intensity
        return material
    }

    // MARK: Foliage

    static func leaf(_ color: RGB, seed: UInt64 = 909) -> SCNMaterial {
        let normal = cached("leaf-n-\(seed)") {
            let noise = Textures.Noise(seed: seed)
            return Textures.normalMap(size: 256, strength: 0.7) { u, v in
                // Veins running the length of the leaf.
                abs(sin(u * .pi * 9.0)) * 0.3 + noise.fbm(u * 20.0, v * 20.0, octaves: 3) * 0.7
            }
        }
        let diffuse = cached("leaf-d-\(color)-\(seed)") {
            let noise = Textures.Noise(seed: seed &+ 6)
            return Textures.image(width: 256, height: 256) { u, v in
                let shade = 0.78 + noise.fbm(u * 9.0, v * 9.0, octaves: 3) * 0.44
                return (Double(color.r) * shade, Double(color.g) * shade,
                        Double(color.b) * shade, 1)
            }
        }
        return pbr { m in
            m.diffuse.contents = diffuse
            m.roughness.contents = 0.54
            m.normal.contents = normal
            m.normal.intensity = 0.6
            m.metalness.contents = 0.0
            m.isDoubleSided = true
            m.clearCoat.contents = 0.25
            m.clearCoatRoughness.contents = 0.4
        }
    }
}
