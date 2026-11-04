import Foundation
import SwiftUI

/// Printer-level settings that belong to this Mac's printer rather than to a design.
final class PrinterSettings: ObservableObject {
    static let shared = PrinterSettings()
    private let d = UserDefaults.standard

    @Published var queue: String { didSet { d.set(queue, forKey: "queue") } }
    /// Firmware image offsets (HOffset / VOffset, -100…100). These are the knobs
    /// that remove a white strip along one edge of the card.
    @Published var hOffset: Int { didSet { d.set(hOffset, forKey: "hOffset") } }
    @Published var vOffset: Int { didSet { d.set(vOffset, forKey: "vOffset") } }
    /// Heat used to bond the film to the card. Too low leaves pale or white edges.
    @Published var transferHeat: Int { didSet { d.set(transferHeat, forKey: "transferHeat") } }
    @Published var transferDwell: Int { didSet { d.set(transferDwell, forKey: "transferDwell") } }
    @Published var dyeSubIntensity: Int { didSet { d.set(dyeSubIntensity, forKey: "dyeSubIntensity") } }
    @Published var resinHeat: Int { didSet { d.set(resinHeat, forKey: "resinHeat") } }

    private init() {
        queue = d.string(forKey: "queue") ?? ""
        hOffset = d.integer(forKey: "hOffset")
        vOffset = d.integer(forKey: "vOffset")
        transferHeat = d.object(forKey: "transferHeat") as? Int ?? 175
        transferDwell = d.object(forKey: "transferDwell") as? Int ?? 20
        dyeSubIntensity = d.integer(forKey: "dyeSubIntensity")
        resinHeat = d.integer(forKey: "resinHeat")
        if queue.isEmpty || !Printer.queues().contains(queue) { queue = Printer.defaultHDPQueue() ?? "" }
    }
}

enum PrintError: LocalizedError {
    case noPrinter, lp(String)
    var errorDescription: String? {
        switch self {
        case .noPrinter: "No HDP5000 printer is set up. Install the Fargo HDP5000 driver and add the printer in System Settings → Printers & Scanners."
        case .lp(let s): "The print system refused the job: \(s)"
        }
    }
}

enum Printer {
    static func run(_ tool: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }

    static func queues() -> [String] {
        run("/usr/bin/lpstat", ["-e"]).1.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func isHDP(_ q: String) -> Bool {
        if q.localizedCaseInsensitiveContains("HDP5000") { return true }
        let ppd = (try? String(contentsOfFile: "/etc/cups/ppd/\(q).ppd", encoding: .utf8)) ?? ""
        return ppd.contains("HDP5000")
    }

    static func defaultHDPQueue() -> String? { queues().first(where: isHDP) }

    static func status(_ q: String) -> String {
        guard !q.isEmpty else { return "No printer selected" }
        let s = run("/usr/bin/lpstat", ["-p", q]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Unknown printer" : s
    }

    static func options(_ design: CardDesign, duplex: Bool) -> [String] {
        let ps = PrinterSettings.shared, p = design.prefs
        let sharp = p.sharpBlack && p.ribbon != "YMC" && p.ribbon != "PremiumResin"
        let kpanel = sharp ? "fullcard" : "none"
        let pairs: [(String, String)] = [
            ("PageSize", "CR80"),
            ("Ribbon", p.ribbon),
            ("Film", p.film),
            ("PrintBothSides", duplex ? "True" : "False"),
            // HID's filter only finds pure black for the resin panel when its
            // colour matching is off; with it on, the K panel is never sent.
            ("ColorMatching", sharp ? "None" : "System"),
            ("kpanelareafront", kpanel),
            ("kpanelareaback", kpanel),
            ("HOffset", String(ps.hOffset)),
            ("VOffset", String(ps.vOffset)),
            ("TransferHeat", String(ps.transferHeat)),
            ("TransferDwell", String(ps.transferDwell)),
            ("DyeSubIntensity", String(ps.dyeSubIntensity)),
            ("ResinHeatFront", String(ps.resinHeat)),
            ("ResinHeatBack", String(ps.resinHeat)),
        ]
        return pairs.flatMap { ["-o", "\($0.0)=\($0.1)"] }
    }

    /// Print one card (both sides if the design is double-sided). Returns the CUPS job id text.
    @discardableResult
    static func printCard(_ design: CardDesign, fields: [String: String], copies: Int = 1, title: String = "ID Card") throws -> String {
        let q = PrinterSettings.shared.queue
        guard !q.isEmpty else { throw PrintError.noPrinter }
        let sides = design.doubleSided ? [design.front, design.back] : [design.front]
        let pdf = Renderer.pdf(design, fields: fields, sides: sides)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("idcard-\(UUID().uuidString).pdf")
        try pdf.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let args = ["-d", q, "-n", String(max(1, copies)), "-t", title] + options(design, duplex: design.doubleSided) + [url.path]
        let (code, out) = run("/usr/bin/lp", args)
        if code != 0 { throw PrintError.lp(out.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run one of HID's maintenance jobs through the installed driver utility.
    static func maintenance(_ command: String) throws {
        let q = PrinterSettings.shared.queue
        guard !q.isEmpty else { throw PrintError.noPrinter }
        let util = "/Library/Printers/Fargo/HDP5000/hdp5000-util"
        let (code, out) = run(util, [q, command])
        if code != 0 { throw PrintError.lp(out) }
    }
}

/// A card that shows exactly where the printed image lands, for setting the offsets.
enum AlignmentCard {
    static var design: CardDesign {
        var d = CardDesign()
        d.orientation = .landscape
        d.doubleSided = false
        d.prefs.sharpBlack = false
        d.front.background = HexColor("#1F5FBFFF")
        let W = Geo.trimLong, H = Geo.trimShort
        var els: [CardElement] = []
        // Ticks every 1 mm from each edge, inward: count the ticks you can see to judge the shift.
        let mm = 72 / 25.4
        for i in 0..<6 {
            let t = CGFloat(i) * mm, len: CGFloat = i % 5 == 0 ? 14 : 8
            for x in stride(from: W * 0.25, through: W * 0.75, by: W * 0.25) {
                els.append(CardElement(kind: .shape, x: x - len / 2, y: t, w: len, h: 0.5, fill: .white))
                els.append(CardElement(kind: .shape, x: x - len / 2, y: H - t - 0.5, w: len, h: 0.5, fill: .white))
            }
            for y in stride(from: H * 0.25, through: H * 0.75, by: H * 0.25) {
                els.append(CardElement(kind: .shape, x: t, y: y - len / 2, w: 0.5, h: len, fill: .white))
                els.append(CardElement(kind: .shape, x: W - t - 0.5, y: y - len / 2, w: 0.5, h: len, fill: .white))
            }
        }
        els.append(CardElement(kind: .text, x: 20, y: 32, w: W - 40, h: 22, text: "ALIGNMENT CARD", fontSize: 14,
                               bold: true, align: .center, color: .white))
        els.append(CardElement(kind: .text, x: 20, y: 56, w: W - 40, h: 60,
                               text: "Colour should reach every edge.\nThe thin frame is 2 mm in from each edge: the gap should match on all four sides.\nTicks are 1 mm apart; the first sits right on the edge.",
                               fontSize: 7.5, align: .center, color: .white))
        // Frame 2 mm inside the trim: compare its gap to the card edge on each side.
        let f = 2 * mm, lw: CGFloat = 0.5
        els.append(CardElement(kind: .shape, x: f, y: f, w: W - 2 * f, h: lw, fill: .white))
        els.append(CardElement(kind: .shape, x: f, y: H - f - lw, w: W - 2 * f, h: lw, fill: .white))
        els.append(CardElement(kind: .shape, x: f, y: f, w: lw, h: H - 2 * f, fill: .white))
        els.append(CardElement(kind: .shape, x: W - f - lw, y: f, w: lw, h: H - 2 * f, fill: .white))
        els.append(CardElement(kind: .text, x: 9, y: 9, w: 30, h: 10, text: "TOP", fontSize: 6, bold: true, color: .white))
        d.front.elements = els
        return d
    }
}
