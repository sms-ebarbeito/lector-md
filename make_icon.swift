// make_icon.swift — genera AppIcon.icns para LectorMD (sin Xcode)
// Uso: swift make_icon.swift <ruta_salida.icns>
import Cocoa

func drawIcon(size sz: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: sz, height: sz))
    image.lockFocus()

    // Fondo degradado: navy oscuro → violeta
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.08, green: 0.10, blue: 0.22, alpha: 1),
            NSColor(srgbRed: 0.18, green: 0.07, blue: 0.28, alpha: 1)
        ],
        atLocations: [0, 1],
        colorSpace: .sRGB
    )!.draw(
        in: NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                         xRadius: sz * 0.205, yRadius: sz * 0.205),
        angle: -55
    )

    // Reflejo sutil en el borde superior
    let shine = NSBezierPath(roundedRect: NSRect(x: 0, y: sz * 0.6, width: sz, height: sz * 0.4),
                             xRadius: sz * 0.205, yRadius: sz * 0.205)
    NSColor(white: 1, alpha: 0.04).setFill()
    shine.fill()

    let center = NSMutableParagraphStyle()
    center.alignment = .center

    // "#" principal
    let hash = NSAttributedString(string: "#", attributes: [
        .font: NSFont.systemFont(ofSize: sz * 0.595, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: center
    ])
    let hh = hash.size().height
    hash.draw(in: NSRect(x: 0, y: (sz - hh) / 2 + sz * 0.055, width: sz, height: hh))

    // ".md" label en azul suave
    let label = NSAttributedString(string: ".md", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: sz * 0.132, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.55, green: 0.72, blue: 1.0, alpha: 0.82),
        .paragraphStyle: center
    ])
    label.draw(in: NSRect(x: 0, y: sz * 0.088, width: sz, height: label.size().height))

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, size: Int) -> Data? {
    let small = NSImage(size: NSSize(width: size, height: size))
    small.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    small.unlockFocus()
    guard let tiff = small.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

// ── main ──────────────────────────────────────────────────────────────────────
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmpDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("LectorMD_iconset_\(Int.random(in: 100000...999999))")

try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

let source = drawIcon(size: 1024)

// Tamaños requeridos por macOS para el .iconset
let specs: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in specs {
    guard let data = pngData(from: source, size: px) else {
        fputs("Error generando \(name)\n", stderr); exit(1)
    }
    try! data.write(to: tmpDir.appendingPathComponent(name))
}

// iconutil convierte el directorio .iconset → .icns
// El directorio debe terminar en .iconset
let iconsetDir = tmpDir.deletingLastPathComponent()
    .appendingPathComponent(tmpDir.lastPathComponent + ".iconset")
    // renombramos la carpeta temporal
try? FileManager.default.moveItem(at: tmpDir, to: iconsetDir)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir.path, "-o", outPath]
try! task.run()
task.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetDir)

if task.terminationStatus == 0 {
    print("✓ \(outPath)")
} else {
    fputs("✗ iconutil falló\n", stderr)
    exit(1)
}
