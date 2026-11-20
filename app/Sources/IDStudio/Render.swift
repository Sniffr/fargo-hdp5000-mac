import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit

/// Draws card sides. The same code feeds the on-screen preview and the PDF
/// sent to the printer, so what you see is what prints.
enum Renderer {
    /// Replace {{Column}} placeholders.
    static func fill(_ s: String, _ fields: [String: String]) -> String {
        guard s.contains("{{") else { return s }
        var out = s
        for (k, v) in fields { out = out.replacingOccurrences(of: "{{\(k)}}", with: v) }
        return out
    }

    /// Draw one side into `ctx`, whose current transform must map the bleed
    /// area (0,0)-(bleed.width, bleed.height) with y pointing DOWN.
    static func draw(_ side: CardSide, orientation: Orientation, fields: [String: String],
                     in ctx: CGContext, showPlaceholders: Bool = false) {
        let bleed = CGRect(origin: .zero, size: orientation.bleed)
        ctx.saveGState()
        ctx.setFillColor(side.background.cg)
        ctx.fill(bleed)
        if let data = side.artwork, let img = cgImage(from: data) {
            let r = artworkRect(img, side: side, orientation: orientation)
            let rot = artworkRotation(side)
            ctx.saveGState()
            ctx.clip(to: bleed)
            var box = r
            if rot != 0 {
                // r is the rotated footprint; draw the upright image turned about its centre.
                ctx.translateBy(x: r.midX, y: r.midY)
                ctx.rotate(by: CGFloat(rot) * .pi / 180)
                let s = rot == 180 ? r.size : CGSize(width: r.height, height: r.width)
                box = CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height)
            }
            if side.artworkExtendEdges == true { extendEdges(img, around: box, ctx: ctx) }
            drawImage(img, in: box, fit: .stretch, ctx: ctx)
            ctx.restoreGState()
        }
        let o = orientation.trimOrigin
        ctx.translateBy(x: o.x, y: o.y)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        for el in side.elements { drawElement(el, fields: fields, ctx: ctx, showPlaceholders: showPlaceholders) }
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Where an imported design lands, in bleed coordinates. "Fill" and
    /// "Stretch" cover the bleed so no white edge shows; "Fit" keeps the whole
    /// design on the physical card. Size and move adjustments apply on top.
    static func artworkRect(_ img: CGImage, side: CardSide, orientation: Orientation) -> CGRect {
        let bleed = CGRect(origin: .zero, size: orientation.bleed)
        let trim = CGRect(origin: orientation.trimOrigin, size: orientation.trim)
        let quarter = artworkRotation(side) % 180 == 90
        let iw = CGFloat(quarter ? img.height : img.width), ih = CGFloat(quarter ? img.width : img.height)
        var r: CGRect
        switch side.artworkFit {
        case .stretch: r = bleed
        case .fill:
            let s = max(bleed.width / iw, bleed.height / ih)
            r = CGRect(x: bleed.midX - iw * s / 2, y: bleed.midY - ih * s / 2, width: iw * s, height: ih * s)
        case .fit:
            let s = min(trim.width / iw, trim.height / ih)
            r = CGRect(x: trim.midX - iw * s / 2, y: trim.midY - ih * s / 2, width: iw * s, height: ih * s)
        }
        let k = CGFloat(side.artworkScale ?? 100) / 100
        let mm: CGFloat = 72 / 25.4
        let c = CGPoint(x: r.midX + CGFloat(side.artworkOffsetX ?? 0) * mm, y: r.midY + CGFloat(side.artworkOffsetY ?? 0) * mm)
        return CGRect(x: c.x - r.width * k / 2, y: c.y - r.height * k / 2, width: r.width * k, height: r.height * k)
    }

    /// Paint the space around a design with its own edge pixels pulled outward
    /// (each side keeps its colours), so a shrunk design shows no border.
    static func extendEdges(_ img: CGImage, around r: CGRect, ctx: CGContext) {
        let w = img.width, h = img.height
        guard w > 8, h > 8 else { return }
        let k = min(2, w / 100, h / 100)           // skip an anti-aliased outermost pixel
        let e: CGFloat = 80, o: CGFloat = 0.5      // reach past any bleed; overlap to avoid seams
        func strip(_ x: Int, _ y: Int, _ sw: Int, _ sh: Int, _ dest: CGRect) {
            if let s = img.cropping(to: CGRect(x: x, y: y, width: sw, height: sh)) { drawImage(s, in: dest, fit: .stretch, ctx: ctx) }
        }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        strip(k, 0, 1, h, CGRect(x: r.minX - e, y: r.minY, width: e + o, height: r.height))
        strip(w - 1 - k, 0, 1, h, CGRect(x: r.maxX - o, y: r.minY, width: e + o, height: r.height))
        strip(0, k, w, 1, CGRect(x: r.minX, y: r.minY - e, width: r.width, height: e + o))
        strip(0, h - 1 - k, w, 1, CGRect(x: r.minX, y: r.maxY - o, width: r.width, height: e + o))
        strip(k, k, 1, 1, CGRect(x: r.minX - e, y: r.minY - e, width: e + o, height: e + o))
        strip(w - 1 - k, k, 1, 1, CGRect(x: r.maxX - o, y: r.minY - e, width: e + o, height: e + o))
        strip(k, h - 1 - k, 1, 1, CGRect(x: r.minX - e, y: r.maxY - o, width: e + o, height: e + o))
        strip(w - 1 - k, h - 1 - k, 1, 1, CGRect(x: r.maxX - o, y: r.maxY - o, width: e + o, height: e + o))
        ctx.restoreGState()
    }

    static func artworkRotation(_ side: CardSide) -> Int { ((side.artworkRotation ?? 0) % 360 + 360) % 360 }

    /// Average colour of an image's four corners, to fill around a shrunk design.
    static func cornerColor(_ img: CGImage) -> HexColor? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let inset = max(1, min(w, h) / 100)      // step in from the very edge
        var sum = [0, 0, 0], n = 0
        for (x, y) in [(inset, inset), (w - 1 - inset, inset), (inset, h - 1 - inset), (w - 1 - inset, h - 1 - inset)] {
            let i = (y * w + x) * 4, a = Int(p[i + 3])
            guard a >= 200 else { continue }        // transparent rounded corners say nothing about the edge
            for c in 0..<3 { sum[c] += min(255, Int(p[i + c]) * 255 / a) }
            n += 1
        }
        guard n > 0 else { return nil }
        return HexColor(String(format: "#%02X%02X%02XFF", sum[0] / n, sum[1] / n, sum[2] / n))
    }

    static func drawElement(_ el: CardElement, fields: [String: String], ctx: CGContext, showPlaceholders: Bool) {
        let r = CGRect(x: 0, y: 0, width: el.w, height: el.h)
        ctx.saveGState()
        ctx.translateBy(x: el.x + el.w / 2, y: el.y + el.h / 2)
        ctx.rotate(by: el.rotation * .pi / 180)
        ctx.translateBy(x: -el.w / 2, y: -el.h / 2)
        let path = shapePath(r, el)

        if el.fill.cg.alpha > 0 { ctx.addPath(path); ctx.setFillColor(el.fill.cg); ctx.fillPath() }

        switch el.kind {
        case .shape:
            break
        case .text:
            drawText(fill(el.text, fields), el, in: r)
        case .image, .photo:
            var img: CGImage? = nil
            if el.kind == .photo, !el.photoField.isEmpty, let p = fields[el.photoField], !p.isEmpty {
                img = loadImage(path: p)
            }
            if img == nil, let d = el.imageData { img = cgImage(from: d) }
            if let img {
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                drawImage(img, in: r, fit: el.fit, ctx: ctx)
                ctx.restoreGState()
            } else if showPlaceholders {
                placeholder(el.kind == .photo ? "Photo" : "Image", in: r, path: path, ctx: ctx)
            }
        case .barcode, .qr:
            let value = fill(el.text, fields)
            if let code = barcode(value, qr: el.kind == .qr, color: el.color.cg) {
                ctx.interpolationQuality = .none
                drawImage(code, in: r, fit: el.kind == .qr ? .fit : .stretch, ctx: ctx)
            } else if showPlaceholders {
                placeholder("Invalid code", in: r, path: path, ctx: ctx)
            }
        }
        if el.strokeWidth > 0, el.stroke.cg.alpha > 0 {
            ctx.addPath(shapePath(r.insetBy(dx: el.strokeWidth / 2, dy: el.strokeWidth / 2), el))
            ctx.setStrokeColor(el.stroke.cg); ctx.setLineWidth(el.strokeWidth); ctx.strokePath()
        }
        ctx.restoreGState()
    }

    static func shapePath(_ r: CGRect, _ el: CardElement) -> CGPath {
        if el.ellipse { return CGPath(ellipseIn: r, transform: nil) }
        let cr = min(el.cornerRadius, min(r.width, r.height) / 2)
        return cr > 0 ? CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil) : CGPath(rect: r, transform: nil)
    }

    static func font(_ el: CardElement, size: CGFloat) -> NSFont {
        var f = NSFont(name: el.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if el.bold { traits.insert(.bold) }
        if el.italic { traits.insert(.italic) }
        if !traits.isEmpty, let g = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(traits), size: size) { f = g }
        return f
    }

    static func attributed(_ s: String, _ el: CardElement, size: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle(); p.alignment = el.align.ns; p.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: s, attributes: [
            .font: font(el, size: size), .foregroundColor: NSColor(cgColor: el.color.cg) ?? .black, .paragraphStyle: p,
        ])
    }

    static func drawText(_ s: String, _ el: CardElement, in r: CGRect) {
        var size = el.fontSize
        var a = attributed(s, el, size: size)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        if el.shrinkToFit {
            // Shrink long names until they fit the box instead of being cut off.
            while size > 4 {
                let b = a.boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude), options: opts)
                let longestWord = s.split(whereSeparator: \.isWhitespace).map { attributed(String($0), el, size: size).size().width }.max() ?? 0
                if b.height <= r.height + 0.5 && longestWord <= r.width + 0.5 { break }
                size -= 0.25; a = attributed(s, el, size: size)
            }
        }
        // Centre a single block of text vertically within its box.
        let b = a.boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude), options: opts)
        let y = max(0, (r.height - b.height) / 2)
        a.draw(with: CGRect(x: 0, y: y, width: r.width, height: r.height - y), options: opts)
    }

    static func placeholder(_ label: String, in r: CGRect, path: CGPath, ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.85, alpha: 0.6)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.8)); ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [2, 2]); ctx.strokePath()
        ctx.restoreGState()
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let a = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: min(9, r.height / 3)),
                                                               .foregroundColor: NSColor.gray, .paragraphStyle: p])
        let h = a.size().height
        a.draw(in: CGRect(x: 0, y: (r.height - h) / 2, width: r.width, height: h))
    }

    /// Draw an image into `r` in a y-down context.
    static func drawImage(_ img: CGImage, in r: CGRect, fit: ImageFit, ctx: CGContext) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        var d = r
        switch fit {
        case .stretch: break
        case .fill, .fit:
            let s = fit == .fill ? max(r.width / iw, r.height / ih) : min(r.width / iw, r.height / ih)
            d = CGRect(x: r.midX - iw * s / 2, y: r.midY - ih * s / 2, width: iw * s, height: ih * s)
        }
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: d.minX, y: d.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: d.size))
        ctx.restoreGState()
    }

    // MARK: images

    // Decoded images are large; keep only a few (bulk printing walks through many).
    private static let cache: NSCache<NSData, CGImage> = { let c = NSCache<NSData, CGImage>(); c.countLimit = 12; return c }()

    static func cgImage(from data: Data) -> CGImage? {
        if let c = cache.object(forKey: data as NSData) { return c }
        var img: CGImage? = nil
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {          // %PDF
            img = PDFDocument(data: data).flatMap { pdfPageImage($0, dpi: 600) }
        } else if let src = CGImageSourceCreateWithData(data as CFData, nil) {
            // Honour the camera's orientation flag so phone photos aren't sideways.
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: 3000]
            img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
        if let img { cache.setObject(img, forKey: data as NSData) }
        return img
    }

    static func loadImage(path: String) -> CGImage? {
        let url = path.hasPrefix("/") || path.hasPrefix("~")
            ? URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            : URL(fileURLWithPath: path, relativeTo: BatchData.baseURL)
        guard let d = try? Data(contentsOf: url) else { return nil }
        return cgImage(from: d)
    }

    static func pdfPageImage(_ doc: PDFDocument, dpi: CGFloat) -> CGImage? {
        guard let page = doc.page(at: 0) else { return nil }
        let box = page.bounds(for: .cropBox)
        let s = dpi / 72
        let w = Int(box.width * s), h = Int(box.height * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: s, y: s); ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: barcodes

    private static let ci = CIContext()

    static func barcode(_ value: String, qr: Bool, color: CGColor) -> CGImage? {
        guard !value.isEmpty else { return nil }
        let out: CIImage?
        if qr {
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(value.utf8); f.correctionLevel = "M"
            out = f.outputImage
        } else {
            guard let ascii = value.data(using: .ascii) else { return nil }
            let f = CIFilter.code128BarcodeGenerator()
            f.message = ascii; f.quietSpace = 0
            out = f.outputImage
        }
        guard let code = out else { return nil }
        // Dark modules -> chosen colour, light -> transparent (card shows through).
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = code.applyingFilter("CIColorInvert")
        guard let m = mask.outputImage else { return nil }
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = CIImage(color: CIColor(cgColor: color)).cropped(to: code.extent)
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = m
        guard let img = blend.outputImage else { return nil }
        return ci.createCGImage(img, from: code.extent)
    }

    // MARK: whole-page output

    /// The PDF sent to the printer: one 159 x 248 pt portrait page per side,
    /// covering the full bleed area.
    static func pdf(_ design: CardDesign, fields: [String: String], sides: [CardSide]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: Geo.pageShort, height: Geo.pageLong)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        for (n, side) in sides.enumerated() {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            var d = design
            if n == 1 && design.prefs.flipBack { d.prefs.flip180.toggle() }
            applyPageTransform(ctx, design: d)
            draw(side, orientation: design.orientation, fields: fields, in: ctx)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Map the bleed area (y-down) onto the portrait printer page (y-up).
    static func applyPageTransform(_ ctx: CGContext, design: CardDesign) {
        if design.prefs.flip180 {
            ctx.translateBy(x: Geo.pageShort, y: Geo.pageLong); ctx.rotate(by: .pi)
        }
        ctx.translateBy(x: 0, y: Geo.pageLong); ctx.scaleBy(x: 1, y: -1)   // now y-down, portrait
        if design.orientation == .landscape {
            // landscape (x, y) -> portrait (pageShort - y, x): turned 90° clockwise
            ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: Geo.pageShort, ty: 0))
        }
    }

    /// Bitmap of one side for the editor.
    static func preview(_ side: CardSide, orientation: Orientation, fields: [String: String], scale: CGFloat) -> CGImage? {
        let s = orientation.bleed
        let w = Int(s.width * scale), h = Int(s.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: scale, y: -scale)
        draw(side, orientation: orientation, fields: fields, in: ctx, showPlaceholders: true)
        return ctx.makeImage()
    }
}
