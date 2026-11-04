import SwiftUI
import UniformTypeIdentifiers

// Card geometry, in PostScript points (1/72 in).
// The physical card is CR80 (85.6 x 53.98 mm). The page the printer driver
// expects is a little larger (159 x 248 pt, portrait): that extra margin is the
// bleed. Backgrounds and imported designs always fill the whole bleed page, so
// a slightly off-centre card never shows an unprinted white strip.
enum Geo {
    static let trimLong: CGFloat = 85.6 / 25.4 * 72      // 242.65
    static let trimShort: CGFloat = 53.98 / 25.4 * 72    // 153.01
    static let pageShort: CGFloat = 159                  // driver page (portrait width)
    static let pageLong: CGFloat = 248                   // driver page (portrait height)
    static let safeInset: CGFloat = 9                    // keep text 1/8 in from the edge
    static let cornerRadius: CGFloat = 3.0 / 25.4 * 72   // ISO 7810 corner, ~3.18 mm
}

enum Orientation: String, Codable, CaseIterable, Identifiable {
    case landscape, portrait
    var id: String { rawValue }
    /// Finished card size (what you design on).
    var trim: CGSize { self == .landscape ? CGSize(width: Geo.trimLong, height: Geo.trimShort)
                                          : CGSize(width: Geo.trimShort, height: Geo.trimLong) }
    /// Printed area including bleed.
    var bleed: CGSize { self == .landscape ? CGSize(width: Geo.pageLong, height: Geo.pageShort)
                                           : CGSize(width: Geo.pageShort, height: Geo.pageLong) }
    /// Where the trim sits inside the bleed area.
    var trimOrigin: CGPoint { CGPoint(x: (bleed.width - trim.width) / 2, y: (bleed.height - trim.height) / 2) }
}

/// RGBA colour stored as hex so documents stay readable.
struct HexColor: Codable, Equatable, Hashable {
    var hex: String
    init(_ hex: String) { self.hex = hex }
    init(cg: CGColor) {
        let c = cg.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? cg
        let p = c.components ?? [0, 0, 0, 1]
        let r, g, b, a: CGFloat
        if p.count >= 3 { (r, g, b) = (p[0], p[1], p[2]); a = p.count > 3 ? p[3] : 1 } else { (r, g, b) = (p[0], p[0], p[0]); a = p.count > 1 ? p[1] : 1 }
        hex = String(format: "#%02X%02X%02X%02X", Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5), Int(a * 255 + 0.5))
    }
    var cg: CGColor {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFF
        return CGColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                       blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }
    static let black = HexColor("#000000FF"), white = HexColor("#FFFFFFFF"), clear = HexColor("#00000000")
}

enum ElementKind: String, Codable, CaseIterable {
    case text, image, photo, barcode, qr, shape
    var label: String {
        switch self {
        case .text: "Text"; case .image: "Logo / Image"; case .photo: "Photo"
        case .barcode: "Barcode"; case .qr: "QR Code"; case .shape: "Shape"
        }
    }
    var symbol: String {
        switch self {
        case .text: "textformat"; case .image: "photo"; case .photo: "person.crop.square"
        case .barcode: "barcode"; case .qr: "qrcode"; case .shape: "square.fill"
        }
    }
}

enum ImageFit: String, Codable, CaseIterable, Identifiable {
    case fill, fit, stretch
    var id: String { rawValue }
    var label: String { switch self { case .fill: "Fill (crop edges)"; case .fit: "Fit inside"; case .stretch: "Stretch" } }
}

enum TextAlign: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var ns: NSTextAlignment { switch self { case .left: .left; case .center: .center; case .right: .right } }
}

/// One item placed on a card. Coordinates are in points, relative to the
/// top-left corner of the finished (trimmed) card, y pointing down.
struct CardElement: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ElementKind
    var name: String = ""
    var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    var rotation: CGFloat = 0          // degrees, clockwise

    // text / barcode / qr content; {{Column}} is replaced from batch data
    var text: String = ""
    var fontName: String = "Helvetica Neue"
    var fontSize: CGFloat = 12
    var bold: Bool = false
    var italic: Bool = false
    var align: TextAlign = .left
    var shrinkToFit: Bool = true
    var color: HexColor = .black

    // image / photo
    var imageData: Data? = nil
    var fit: ImageFit = .fill
    /// Batch column holding a photo file path (photo elements).
    var photoField: String = ""

    // shape (and image frame)
    var fill: HexColor = .clear
    var stroke: HexColor = .clear
    var strokeWidth: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var ellipse: Bool = false

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
    }
}

struct CardSide: Codable, Equatable {
    var background: HexColor = .white
    /// A full-card artwork (made in another app). Always printed to the bleed edge.
    var artwork: Data? = nil
    var artworkFit: ImageFit = .fill
    // Optional so documents saved before these existed still open.
    var artworkScale: Double? = nil      // percent of the fitted size
    var artworkOffsetX: Double? = nil    // mm, + = right
    var artworkOffsetY: Double? = nil    // mm, + = down
    var elements: [CardElement] = []
}

struct PrintPrefs: Codable, Equatable {
    var ribbon = "YMCK"
    var sharpBlack = true          // send pure black text/barcodes to the resin K panel
    var film = "Clear"
    var flip180 = false            // if cards come out upside down
    var flipBack = false           // if only the back comes out upside down
}

struct CardDesign: Codable, Equatable {
    var version = 1
    var orientation: Orientation = .landscape
    var doubleSided = false
    var front = CardSide()
    var back = CardSide()
    var prefs = PrintPrefs()
}

extension UTType {
    static let idCard = UTType(exportedAs: "com.stdiox.hdp5000.idcard", conformingTo: .json)
}

struct CardDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.idCard, .json] }
    var design: CardDesign

    init(design: CardDesign = Templates.employee) { self.design = design }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        design = try JSONDecoder().decode(CardDesign.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try enc.encode(design))
    }
}

enum Templates {
    static var employee: CardDesign {
        var d = CardDesign()
        d.orientation = .landscape
        d.doubleSided = true
        let navy = HexColor("#13315CFF"), accent = HexColor("#2E86DEFF")
        d.front.background = .white
        d.front.elements = [
            CardElement(kind: .shape, name: "Header band", x: -4, y: -4, w: Geo.trimLong + 8, h: 40, fill: navy),
            CardElement(kind: .shape, name: "Accent line", x: -4, y: 36, w: Geo.trimLong + 8, h: 3, fill: accent),
            CardElement(kind: .text, name: "Organisation", x: 12, y: 9, w: 170, h: 20,
                        text: "{{Organisation}}", fontSize: 14, bold: true, color: .white),
            CardElement(kind: .image, name: "Logo", x: Geo.trimLong - 44, y: 5, w: 30, h: 30, fit: .fit),
            CardElement(kind: .photo, name: "Photo", x: 12, y: 48, w: 66, h: 84, photoField: "Photo",
                        stroke: navy, strokeWidth: 1, cornerRadius: 3),
            CardElement(kind: .text, name: "Name", x: 88, y: 50, w: 145, h: 22,
                        text: "{{Name}}", fontSize: 15, bold: true, color: navy),
            CardElement(kind: .text, name: "Title", x: 88, y: 72, w: 145, h: 15,
                        text: "{{Title}}", fontSize: 9.5, color: HexColor("#444444FF")),
            CardElement(kind: .text, name: "ID label", x: 88, y: 92, w: 145, h: 11,
                        text: "ID NO.", fontSize: 6.5, bold: true, color: accent),
            CardElement(kind: .text, name: "ID number", x: 88, y: 102, w: 145, h: 15,
                        text: "{{ID}}", fontSize: 11, bold: true, color: .black),
            CardElement(kind: .barcode, name: "Barcode", x: 88, y: 120, w: 140, h: 24, text: "{{ID}}"),
        ]
        d.back.background = .white
        d.back.elements = [
            CardElement(kind: .shape, name: "Footer band", x: -4, y: Geo.trimShort - 22, w: Geo.trimLong + 8, h: 26, fill: navy),
            CardElement(kind: .text, name: "Notice", x: 14, y: 14, w: 150, h: 70,
                        text: "This card is the property of {{Organisation}}. If found, please return it to the address below.",
                        fontSize: 8, color: HexColor("#333333FF")),
            CardElement(kind: .qr, name: "QR", x: Geo.trimLong - 74, y: 14, w: 60, h: 60, text: "{{ID}}"),
            CardElement(kind: .text, name: "Valid", x: 14, y: 92, w: 150, h: 14,
                        text: "Valid until: {{Expiry}}", fontSize: 8.5, bold: true, color: .black),
            CardElement(kind: .text, name: "Footer", x: 14, y: Geo.trimShort - 17, w: Geo.trimLong - 28, h: 12,
                        text: "{{Organisation}}", fontSize: 7.5, align: .center, color: .white),
        ]
        return d
    }

    static var blank: CardDesign { var d = CardDesign(); d.doubleSided = false; return d }

    /// Sample values shown in the editor when no batch data is loaded.
    static let sampleFields: [String: String] = [
        "Organisation": "Your Organisation", "Name": "Jane Wanjiru", "Title": "Operations Manager",
        "ID": "EMP-000123", "Expiry": "12/2027", "Photo": "",
    ]
}
