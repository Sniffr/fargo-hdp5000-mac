import SwiftUI

struct PrinterSettingsView: View {
    @ObservedObject var ps = PrinterSettings.shared
    @State private var queues: [String] = Printer.queues()
    @State private var status = ""
    @State private var note: String? = nil

    var body: some View {
        Form {
            Section("Printer") {
                Picker("Printer", selection: $ps.queue) {
                    if ps.queue.isEmpty { Text("None").tag("") }
                    ForEach(queues, id: \.self) { q in Text(Printer.isHDP(q) ? "\(q)  (HDP5000)" : q).tag(q) }
                }
                Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }

            Section {
                Text("Removing a white edge").font(.headline)
                // Measured on a real HDP5000 with a landscape card held TOP up:
                // HOffset +1 moves the print ~0.2 mm LEFT, VOffset +1 moves it
                // ~0.085 mm UP (1/300 in). White on an edge means the print has
                // drifted away from it, so the arrow moves the print toward it.
                Text("1. Print the alignment card.  2. Hold it with TOP at the top-left and look for white along an edge.  3. Press the arrow pointing at that edge (each step moves the print about 0.2 mm sideways or 0.1 mm up/down). Print again to check.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 24) {
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        GridRow { Color.clear.frame(width: 1, height: 1); nudge("arrow.up", "White at top") { ps.vOffset += step }; Color.clear.frame(width: 1, height: 1) }
                        GridRow { nudge("arrow.left", "White on left") { ps.hOffset += step }
                                  Text("move").font(.caption2).foregroundStyle(.secondary)
                                  nudge("arrow.right", "White on right") { ps.hOffset -= step } }
                        GridRow { Color.clear.frame(width: 1, height: 1); nudge("arrow.down", "White at bottom") { ps.vOffset -= step }; Color.clear.frame(width: 1, height: 1) }
                    }
                    VStack(alignment: .leading) {
                        Stepper("Horizontal offset: \(ps.hOffset)", value: $ps.hOffset, in: -100...100)
                        Stepper("Vertical offset: \(ps.vOffset)", value: $ps.vOffset, in: -100...100)
                        Picker("Step", selection: $step) { Text("1").tag(1); Text("3").tag(3); Text("5").tag(5) }.pickerStyle(.segmented)
                        Button("Reset to 0") { ps.hOffset = 0; ps.vOffset = 0 }
                    }
                }
                Text("The setting is remembered for every card.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Fine-tune by measuring") {
                    Text("The alignment card has a thin frame 2 mm inside each edge. Measure the gap between the card edge and the frame on each side (a ruler, or compare by eye) and enter it in mm.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading) {
                        GridRow { Text("Left"); gapField($gapL); Text("Right"); gapField($gapR) }
                        GridRow { Text("Top"); gapField($gapT); Text("Bottom"); gapField($gapB) }
                    }
                    Button("Apply correction") { applyGaps() }
                }
                Button { printAlignment() } label: { Label("Print Alignment Card", systemImage: "viewfinder") }
            }

            Section("Film transfer") {
                Stepper("Transfer heat: \(ps.transferHeat) (default 175)", value: $ps.transferHeat, in: 150...190)
                Picker("Transfer dwell", selection: $ps.transferDwell) { Text("10").tag(10); Text("20 (default)").tag(20); Text("30").tag(30) }
                Text("If the edges are pale or the film peels at the edge rather than a clean white strip, raise transfer heat by 5 and clean the printer.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Print darkness") {
                Stepper("Colour intensity: \(ps.dyeSubIntensity)", value: $ps.dyeSubIntensity, in: -50...50)
                Stepper("Black (resin) heat: \(ps.resinHeat)", value: $ps.resinHeat, in: -50...50)
            }

            Section("Maintenance") {
                HStack {
                    Button("Clean Printer") { maint("clean") }
                    Button("Ribbon Calibration") { maint("ribbon-cal") }
                    Button("Film Calibration") { maint("film-cal") }
                }
                Button("Print HID Colour Test Card") { maint("test-ymck") }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .onChange(of: ps.queue) { _ in refresh() }
    }

    @State private var step = 3
    @State private var gapL = 2.0
    @State private var gapR = 2.0
    @State private var gapT = 2.0
    @State private var gapB = 2.0

    func gapField(_ v: Binding<Double>) -> some View {
        TextField("mm", value: v, format: .number.precision(.fractionLength(0...2))).frame(width: 60)
    }

    /// Unequal gaps mean the print is off-centre by half the difference.
    func applyGaps() {
        let mmPerH = 0.2, mmPerV = 25.4 / 300
        ps.hOffset = (ps.hOffset + Int((((gapL - gapR) / 2) / mmPerH).rounded())).clamped(-100, 100)   // + moves left
        ps.vOffset = (ps.vOffset + Int((((gapT - gapB) / 2) / mmPerV).rounded())).clamped(-100, 100)   // + moves up
        gapL = 2; gapR = 2; gapT = 2; gapB = 2
    }

    func nudge(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { action(); ps.hOffset = ps.hOffset.clamped(-100, 100); ps.vOffset = ps.vOffset.clamped(-100, 100) }) {
            Image(systemName: symbol).frame(width: 22, height: 18)
        }.help(help)
    }

    func refresh() {
        queues = Printer.queues()
        status = Printer.status(ps.queue)
    }

    func printAlignment() {
        do { try Printer.printCard(AlignmentCard.design, fields: [:], title: "Alignment card"); note = "Alignment card sent." }
        catch { note = error.localizedDescription }
    }

    func maint(_ cmd: String) {
        do { try Printer.maintenance(cmd); note = "Sent \(cmd)." } catch { note = error.localizedDescription }
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(hi, Swift.max(lo, self)) }
}

/// Print every row of the loaded spreadsheet.
struct BatchSheet: View {
    let document: CardDocument
    @Binding var batch: BatchData
    @Binding var rowIndex: Int
    let done: () -> Void
    let report: (String) -> Void
    @State private var selected = Set<Int>()
    @State private var progress: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Print cards from \(batch.fileName)").font(.title3).bold()
            Text("Select rows to print only those, or print everything.").foregroundStyle(.secondary)
            Table(batch.rows.indices.map { BatchRow(id: $0, element: batch.rows[$0]) }, selection: $selected) {
                TableColumn("#") { r in Text("\(r.id + 1)").monospacedDigit() }.width(30)
                TableColumn(batch.columns.first ?? "") { r in Text(r.element[batch.columns.first ?? ""] ?? "") }
                TableColumn(batch.columns.dropFirst().first ?? "") { r in Text(r.element[batch.columns.dropFirst().first ?? ""] ?? "") }
                TableColumn(batch.columns.dropFirst(2).first ?? "") { r in Text(r.element[batch.columns.dropFirst(2).first ?? ""] ?? "") }
            }
            .frame(minHeight: 260)
            if let progress { ProgressView(value: Double(progress), total: Double(max(1, toPrint.count))) }
            HStack {
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Spacer()
                Button(selected.isEmpty ? "Print All \(batch.rows.count)" : "Print \(selected.count) Selected") { run() }
                    .keyboardShortcut(.defaultAction).disabled(progress != nil)
            }
        }
        .padding(20)
        .frame(width: 620, height: 440)
    }

    var toPrint: [Int] { selected.isEmpty ? Array(batch.rows.indices) : selected.sorted() }

    func run() {
        let rows = toPrint
        progress = 0
        var failures: [String] = []
        for (n, i) in rows.enumerated() {
            let f = batch.rows[i]
            do { try Printer.printCard(document.design, fields: f, title: "ID Card – \(f["Name"] ?? "#\(i + 1)")") }
            catch { failures.append("row \(i + 1): \(error.localizedDescription)") }
            progress = n + 1
        }
        report(failures.isEmpty ? "Sent \(rows.count) cards to the printer." : "Some cards failed: " + failures.joined(separator: "; "))
        done()
    }
}

struct BatchRow: Identifiable { let id: Int; let element: [String: String] }
