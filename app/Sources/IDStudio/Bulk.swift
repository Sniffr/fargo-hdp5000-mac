import SwiftUI
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// MARK: - Folder scan

/// One card found in a folder: a front file and, when its name matches, a back file.
struct BulkCard: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var front: URL?
    var back: URL?
    var include = true
    var note: String? = nil
    /// Extra clockwise turn for the back, chosen in the preview list.
    var backTurn = 0
}

enum BulkScan {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "pdf", "bmp", "gif", "webp"]

    enum Side { case front, back }

    /// "front" or "back" as its own word: `id_front`, `Front-2`, `john back (1)`,
    /// but not the "back" in "background".
    private static let sideWord = try! NSRegularExpression(pattern: "(?<![A-Za-z])(front|back)(?![A-Za-z])",
                                                           options: [.caseInsensitive])

    /// The side named in a file name, and the name with that word taken out.
    /// `id_front(1)` and `id_back(1)` both give the key "id_(1)", so they pair up;
    /// `id_front` gives "id_", a different card.
    static func classify(_ fileName: String) -> (side: Side?, key: String, display: String) {
        let base = (fileName as NSString).deletingPathExtension
        let ns = base as NSString
        guard let m = sideWord.matches(in: base, range: NSRange(location: 0, length: ns.length)).last else {
            return (nil, normalize(base), tidy(base))
        }
        let side: Side = ns.substring(with: m.range).lowercased() == "front" ? .front : .back
        let rest = ns.replacingCharacters(in: m.range, with: "")
        return (side, normalize(rest), tidy(rest))
    }

    /// Spacing and case differences don't make two files different cards.
    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    private static func tidy(_ s: String) -> String {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " _-.").union(.whitespaces))
        let spaced = t.replacingOccurrences(of: "[_\\-\\s]+\\(", with: " (", options: .regularExpression)
        return spaced.isEmpty ? "Card" : spaced
    }

    static func scan(_ folder: URL) -> [BulkCard] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        var groups: [String: (display: String, fronts: [URL], backs: [URL], plain: [URL])] = [:]
        for url in files where extensions.contains(url.pathExtension.lowercased()) {
            let c = classify(url.lastPathComponent)
            var g = groups[c.key] ?? (c.display, [], [], [])
            switch c.side {
            case .front: g.fronts.append(url)
            case .back: g.backs.append(url)
            case nil: g.plain.append(url)
            }
            groups[c.key] = g
        }
        var cards: [BulkCard] = []
        for (_, g) in groups {
            let byName: (URL, URL) -> Bool = { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let fronts = g.fronts.sorted(by: byName), backs = g.backs.sorted(by: byName)
            for i in 0..<max(fronts.count, backs.count) {
                let f = i < fronts.count ? fronts[i] : nil, b = i < backs.count ? backs[i] : nil
                var card = BulkCard(name: g.display, front: f, back: b)
                if f == nil {
                    card.include = false
                    card.note = "Back with no matching front: skipped"
                } else if b == nil {
                    card.note = "No back found: prints one-sided"
                } else if fronts.count > 1 || backs.count > 1 {
                    card.note = "Several files share this name: check the pairing"
                }
                cards.append(card)
            }
            for p in g.plain.sorted(by: byName) {
                cards.append(BulkCard(name: tidy((p.lastPathComponent as NSString).deletingPathExtension), front: p,
                                      note: "No \"front\" or \"back\" in the name: prints one-sided"))
            }
        }
        return cards.sorted {
            let a = $0.front ?? $0.back!, b = $1.front ?? $1.back!
            let byName = $0.name.localizedStandardCompare($1.name)
            return byName == .orderedSame ? a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
                                          : byName == .orderedAscending
        }
    }

    // MARK: building a printable card

    /// Card orientation follows the front; a back drawn the other way round is turned to fit.
    static func layout(front: CGSize, back: CGSize?) -> (Orientation, backRotation: Int) {
        let landscape = front.width >= front.height
        guard let back else { return (landscape ? .landscape : .portrait, 0) }
        return (landscape ? .landscape : .portrait, (back.width >= back.height) == landscape ? 0 : 90)
    }

    static func side(_ data: Data, image: CGImage, rotation: Int, opts: BulkConfig) -> CardSide {
        var s = CardSide()
        s.artwork = data
        s.artworkFit = .fit
        s.artworkScale = opts.scale
        s.artworkRotation = rotation == 0 ? nil : rotation
        s.artworkExtendEdges = opts.matchEdges ? true : nil
        return s
    }

    static func design(_ card: BulkCard, opts: BulkConfig) throws -> CardDesign {
        guard let fu = card.front else { throw CocoaError(.fileNoSuchFile) }
        let fd = try Data(contentsOf: fu)
        guard let fi = Renderer.cgImage(from: fd) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: fu.path]) }
        var bd: Data? = nil, bi: CGImage? = nil
        if let bu = card.back {
            bd = try Data(contentsOf: bu)
            bi = Renderer.cgImage(from: bd!)
            if bi == nil { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: bu.path]) }
        }
        let (orientation, auto) = layout(front: CGSize(width: fi.width, height: fi.height),
                                          back: bi.map { CGSize(width: $0.width, height: $0.height) })
        let rot = (auto + card.backTurn) % 360
        var d = CardDesign()
        d.orientation = orientation
        d.front = side(fd, image: fi, rotation: 0, opts: opts)
        if let bd, let bi {
            d.back = side(bd, image: bi, rotation: rot, opts: opts)
            d.doubleSided = true
        } else {
            d.doubleSided = false
        }
        d.prefs.ribbon = opts.ribbon
        d.prefs.sharpBlack = false
        d.prefs.flipBack = opts.flipBack
        return d
    }

    // MARK: previews

    /// A small copy of a file for the preview list (images and the first page of PDFs).
    static func thumbnail(_ url: URL, maxPixels: Int = 420) -> CGImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let ns = page.thumbnail(of: NSSize(width: maxPixels, height: maxPixels), for: .cropBox)
            return ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// How a side will print, cropped to the card outline.
    static func cardPreview(_ img: CGImage, orientation: Orientation, rotation: Int, opts: BulkConfig, scale: CGFloat) -> CGImage? {
        guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return nil }
        let s = side(png, image: img, rotation: rotation, opts: opts)
        guard let full = Renderer.preview(s, orientation: orientation, fields: [:], scale: scale) else { return nil }
        let o = orientation.trimOrigin, t = orientation.trim
        return full.cropping(to: CGRect(x: o.x * scale, y: o.y * scale, width: t.width * scale, height: t.height * scale).integral)
    }
}

// MARK: - Options (remembered between runs)

/// A plain copy of the options, safe to hand to background work.
struct BulkConfig {
    var scale = 98.0, matchEdges = true, flipBack = false, ribbon = "YMCK", copies = 1
}

final class BulkOptions: ObservableObject {
    private let d = UserDefaults.standard
    /// Size of each design as a percent of "fits the card exactly". A little under 100
    /// leaves room for the printer's ±0.25 mm card-to-card drift.
    @Published var scale: Double { didSet { d.set(scale, forKey: "bulk.scale") } }
    @Published var matchEdges: Bool { didSet { d.set(matchEdges, forKey: "bulk.matchEdges") } }
    @Published var flipBack: Bool { didSet { d.set(flipBack, forKey: "bulk.flipBack") } }
    @Published var ribbon: String { didSet { d.set(ribbon, forKey: "bulk.ribbon") } }
    @Published var copies: Int { didSet { d.set(copies, forKey: "bulk.copies") } }
    @Published var lastFolder: String { didSet { d.set(lastFolder, forKey: "bulk.folder") } }

    init() {
        scale = d.object(forKey: "bulk.scale") as? Double ?? 98
        matchEdges = d.object(forKey: "bulk.matchEdges") as? Bool ?? true
        flipBack = d.bool(forKey: "bulk.flipBack")
        ribbon = d.string(forKey: "bulk.ribbon") ?? "YMCK"
        copies = max(1, d.integer(forKey: "bulk.copies"))
        lastFolder = d.string(forKey: "bulk.folder") ?? ""
    }

    var config: BulkConfig { BulkConfig(scale: scale, matchEdges: matchEdges, flipBack: flipBack, ribbon: ribbon, copies: copies) }

    /// Changes that alter how cards look, so previews redraw.
    var previewKey: String { "\(scale)|\(matchEdges)" }
}

// MARK: - Window

struct BulkPrintView: View {
    @StateObject private var opts = BulkOptions()
    @ObservedObject private var printer = PrinterSettings.shared
    @State private var folder: URL? = nil
    @State private var cards: [BulkCard] = []
    @State private var confirming = false
    @State private var progress: Int? = nil
    @State private var total = 0
    @State private var stopRequested = false
    @State private var status: String? = nil
    @State private var dropTargeted = false

    private var selected: [BulkCard] { cards.filter { $0.include && $0.front != nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if folder == nil {
                emptyState
            } else if cards.isEmpty {
                ContentUnavailable(title: "No card pictures in this folder",
                                   message: "Add PNG, JPG, HEIC or PDF files named like id_front.png and id_back.png.")
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                let dir = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                DispatchQueue.main.async { load(dir ? url : url.deletingLastPathComponent()) }
            }
            return true
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(6) } }
        .onAppear {
            if folder == nil, !opts.lastFolder.isEmpty, FileManager.default.fileExists(atPath: opts.lastFolder) {
                load(URL(fileURLWithPath: opts.lastFolder))
            }
        }
        .alert("Print \(selected.count) card\(selected.count == 1 ? "" : "s")?", isPresented: $confirming) {
            Button("Print") { startPrinting() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let two = selected.filter { $0.back != nil }.count
            Text("\(two) two-sided, \(selected.count - two) one-sided" +
                 (opts.copies > 1 ? ", \(opts.copies) copies of each" : "") +
                 ". Each design is fitted inside the card at \(Int(opts.scale))% so nothing is cut off.\nPrinter: \(printer.queue.isEmpty ? "none set up" : printer.queue)")
        }
    }

    // MARK: pieces

    var header: some View {
        HStack(spacing: 10) {
            Button { chooseFolder() } label: { Label("Choose Folder…", systemImage: "folder") }
            if let folder {
                Text(folder.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button { load(folder) } label: { Image(systemName: "arrow.clockwise") }.help("Scan the folder again")
            }
            Spacer()
            if !cards.isEmpty { Text(summary).foregroundStyle(.secondary).font(.callout) }
        }
        .padding(12)
    }

    var summary: String {
        let two = cards.filter { $0.front != nil && $0.back != nil }.count
        let one = cards.filter { $0.front != nil && $0.back == nil }.count
        let skipped = cards.filter { $0.front == nil }.count
        return "\(cards.count) found · \(two) two-sided · \(one) one-sided" + (skipped > 0 ? " · \(skipped) skipped" : "")
    }

    var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus").font(.system(size: 46)).foregroundStyle(.secondary)
            Text("Drop a folder of card pictures here").font(.title2)
            Text("Name each card's files with **front** and **back**: `id_front.png` and `id_back.png` make one card,\n`id_front(1).png` and `id_back(1).png` another. Files without front/back print one-sided.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choose Folder…") { chooseFolder() }.controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("").frame(width: 24)
                    Text("Card").frame(width: 170, alignment: .leading)
                    Text("Front").frame(width: 200, alignment: .leading)
                    Text("Back").frame(width: 200, alignment: .leading)
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                ForEach($cards) { $card in
                    BulkRow(card: $card, opts: opts, index: (cards.firstIndex(where: { $0.id == card.id }) ?? 0) + 1)
                        .contextMenu {
                            Button("Open in Designer") { if let d = try? BulkScan.design(card, opts: opts.config) { NewDoc.open(d) } }
                            if let f = card.front { Button("Show Front in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
                        }
                    Divider()
                }
            }
        }
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Text("Size")
                    Slider(value: $opts.scale, in: 85...100, step: 0.5).frame(width: 140)
                    Text(String(format: "%.1f%%", opts.scale)).monospacedDigit().frame(width: 48, alignment: .leading)
                }
                .help("100% fits the card exactly. A little less leaves a safety margin so nothing at the edge is lost.")
                Toggle("Fill margins with the design's edge colours", isOn: $opts.matchEdges)
                Toggle("Back comes out upside down", isOn: $opts.flipBack)
            }
            HStack(spacing: 14) {
                Picker("Ribbon", selection: $opts.ribbon) {
                    Text("YMCK").tag("YMCK"); Text("YMC").tag("YMC"); Text("YMCKK").tag("YMCKK"); Text("YMCKH").tag("YMCKH")
                }.frame(width: 150)
                Stepper("Copies of each: \(opts.copies)", value: $opts.copies, in: 1...50)
                Spacer()
                if let progress {
                    ProgressView(value: Double(progress), total: Double(max(total, 1))).frame(width: 140)
                    Text("\(progress)/\(total)").monospacedDigit()
                    Button("Stop") { stopRequested = true }.disabled(stopRequested)
                } else {
                    if let status { Text(status).foregroundStyle(.secondary).lineLimit(2) }
                    Button { confirming = true } label: {
                        Label("Print \(selected.count) Card\(selected.count == 1 ? "" : "s")", systemImage: "printer")
                    }
                    .keyboardShortcut("p")
                    .controlSize(.large)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .padding(12)
    }

    // MARK: actions

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.message = "Choose the folder with the card pictures"
        if let folder { p.directoryURL = folder }
        guard p.runModal() == .OK, let url = p.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        folder = url
        opts.lastFolder = url.path
        cards = BulkScan.scan(url)
        status = nil
    }

    func startPrinting() {
        let jobs = selected, o = opts.config
        total = jobs.count
        progress = 0
        stopRequested = false
        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            var done = 0
            for card in jobs {
                if DispatchQueue.main.sync(execute: { stopRequested }) { break }
                do {
                    let d = try BulkScan.design(card, opts: o)
                    try Printer.printCard(d, fields: [:], copies: o.copies, title: "ID \(card.name)")
                } catch {
                    failures.append("\(card.name): \(error.localizedDescription)")
                }
                done += 1
                let n = done
                DispatchQueue.main.async { progress = n }
            }
            let stopped = done < jobs.count
            DispatchQueue.main.async {
                progress = nil
                if failures.isEmpty {
                    status = stopped ? "Stopped after \(done) of \(jobs.count). Cards already sent will still print."
                                     : "Sent \(done) card\(done == 1 ? "" : "s") to the printer."
                } else {
                    status = "\(done - failures.count) sent, \(failures.count) failed: " + failures.joined(separator: "; ")
                    NSSound.beep()
                }
            }
        }
    }
}

/// One detected card: thumbnails of how each side will print.
struct BulkRow: View {
    @Binding var card: BulkCard
    @ObservedObject var opts: BulkOptions
    let index: Int
    @State private var front: CGImage? = nil
    @State private var back: CGImage? = nil
    @State private var rotatedBack = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Toggle("", isOn: $card.include).labelsHidden().disabled(card.front == nil).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(index). \(card.name)").font(.headline).lineLimit(2)
                if let note = card.note {
                    Text(note).font(.caption).foregroundStyle(card.front == nil ? .red : .orange)
                }
                if rotatedBack {
                    Text("Back turned 90° to match the front").font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(width: 170, alignment: .leading)
            sideCell(front, url: card.front, label: "FRONT")
            sideCell(back, url: card.back, label: "BACK")
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .opacity(card.include ? 1 : 0.5)
        .task(id: "\(card.front?.path ?? "")|\(card.back?.path ?? "")|\(card.backTurn)|\(opts.previewKey)") { await render() }
    }

    @ViewBuilder func sideCell(_ img: CGImage?, url: URL?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let img {
                    Image(decorative: img, scale: 2).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25)))
                } else if url != nil {
                    ProgressView().controlSize(.small)
                } else {
                    RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary)
                        .overlay(Text("none").font(.caption).foregroundStyle(.tertiary))
                }
            }
            .frame(width: 180, height: 114, alignment: .leading)
            HStack(spacing: 4) {
                Text(label).font(.caption2.bold()).foregroundStyle(label == "FRONT" ? Color.accentColor : Color.purple)
                Text(url?.lastPathComponent ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if label == "BACK", url != nil, card.front != nil {
                    Spacer(minLength: 2)
                    Button { card.backTurn = (card.backTurn + 90) % 360 } label: { Label("Turn", systemImage: "rotate.right") }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Turn the back 90° if it would print sideways or upside down")
                }
            }
            .frame(width: 180, alignment: .leading)
        }
        .frame(width: 200, alignment: .leading)
    }

    func render() async {
        let card = card, o = opts.config
        let result = await Task.detached(priority: .utility) { () -> (CGImage?, CGImage?, Bool) in
            let f = card.front.flatMap { BulkScan.thumbnail($0) }
            let b = card.back.flatMap { BulkScan.thumbnail($0) }
            let size = { (i: CGImage) in CGSize(width: i.width, height: i.height) }
            let ref = f ?? b
            guard let ref else { return (nil, nil, false) }
            let (orientation, auto) = BulkScan.layout(front: size(ref), back: f != nil ? b.map(size) : nil)
            let rot = (auto + card.backTurn) % 360
            let scale: CGFloat = 1.4   // 2x for Retina, drawn at 180 pt wide
            return (f.flatMap { BulkScan.cardPreview($0, orientation: orientation, rotation: 0, opts: o, scale: scale) },
                    b.flatMap { BulkScan.cardPreview($0, orientation: orientation, rotation: rot, opts: o, scale: scale) },
                    auto != 0)
        }.value
        front = result.0; back = result.1; rotatedBack = result.2
    }
}

/// Simple stand-in for ContentUnavailableView (macOS 14+).
struct ContentUnavailable: View {
    let title: String, message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
