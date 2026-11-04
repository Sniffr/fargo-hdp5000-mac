import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Artwork {
    static let types: [UTType] = [.png, .jpeg, .heic, .tiff, .pdf, .bmp, .gif, .image]

    static func pick(message: String) -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    static func orientation(of data: Data) -> Orientation? {
        guard let img = Renderer.cgImage(from: data) else { return nil }
        return img.width >= img.height ? .landscape : .portrait
    }
}

enum SideSel: String, CaseIterable, Identifiable { case front = "Front", back = "Back"; var id: String { rawValue } }

struct EditorView: View {
    @Binding var document: CardDocument
    @State private var sideSel: SideSel = .front
    @State private var selection: UUID? = nil
    @State private var batch = BatchData()
    @State private var rowIndex = 0
    @State private var zoom: CGFloat = 2.4
    @State private var message: String? = nil
    @State private var showBatch = false
    @State private var showPrinter = false
    @State private var copies = 1

    private var design: CardDesign { document.design }

    var sideBinding: Binding<CardSide> {
        Binding(get: { sideSel == .front || !design.doubleSided ? document.design.front : document.design.back },
                set: { if sideSel == .front || !document.design.doubleSided { document.design.front = $0 } else { document.design.back = $0 } })
    }

    var fields: [String: String] {
        guard !batch.rows.isEmpty else { return Templates.sampleFields }
        return batch.rows[min(rowIndex, batch.rows.count - 1)]
    }

    var body: some View {
        HSplitView {
            Sidebar(side: sideBinding, selection: $selection, sideSel: $sideSel, doubleSided: design.doubleSided)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            VStack(spacing: 0) {
                CanvasView(side: sideBinding, selection: $selection, orientation: design.orientation, fields: fields, zoom: zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                StatusBar(batch: batch, rowIndex: $rowIndex, zoom: $zoom, message: message)
            }
            .frame(minWidth: 520)
            Inspector(document: $document, side: sideBinding, selection: $selection, columns: batch.columns)
                .frame(minWidth: 250, idealWidth: 270, maxWidth: 320)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showBatch) {
            BatchSheet(document: document, batch: $batch, rowIndex: $rowIndex, done: { showBatch = false }, report: { message = $0 })
        }
        .sheet(isPresented: $showPrinter) {
            VStack(spacing: 0) {
                PrinterSettingsView()
                HStack { Spacer(); Button("Done") { showPrinter = false }.keyboardShortcut(.defaultAction) }.padding()
            }.frame(width: 540)
        }
        .onDeleteCommand { deleteSelected() }
        .onChange(of: design.doubleSided) { on in if !on { sideSel = .front } }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Orientation", selection: $document.design.orientation) {
                Image(systemName: "rectangle").tag(Orientation.landscape).help("Landscape")
                Image(systemName: "rectangle.portrait").tag(Orientation.portrait).help("Portrait")
            }.pickerStyle(.segmented)
        }
        ToolbarItemGroup {
            Menu {
                Button("Use a design file for the Front…") { importArtwork(front: true) }
                Button("Use a design file for the Back…") { importArtwork(front: false) }
                Divider()
                Button("Remove design file from this side") { sideBinding.wrappedValue.artwork = nil }
                    .disabled(sideBinding.wrappedValue.artwork == nil)
            } label: { Label("Import Design", systemImage: "square.and.arrow.down") }
                .help("Use a full card design made in another app (PNG, JPG, HEIC or PDF). It is printed edge to edge.")

            Button { loadCSV() } label: { Label("Load Data", systemImage: "tablecells") }
                .help("Load a spreadsheet (CSV) to fill {{placeholders}} and print many cards")

            Button { showPrinter = true } label: { Label("Printer", systemImage: "gearshape") }
                .help("Printer, edge alignment and heat settings")

            Stepper("×\(copies)", value: $copies, in: 1...500).help("Copies")

            Button { printCurrent() } label: { Label("Print", systemImage: "printer") }
                .keyboardShortcut("p")
                .help("Print this card")

            if !batch.rows.isEmpty {
                Button { showBatch = true } label: { Label("Print All (\(batch.rows.count))", systemImage: "printer.filled.and.paper") }
            }
        }
    }

    func deleteSelected() {
        guard let id = selection else { return }
        sideBinding.wrappedValue.elements.removeAll { $0.id == id }
        selection = nil
    }

    func importArtwork(front: Bool) {
        guard let data = Artwork.pick(message: "Choose the \(front ? "front" : "back") design") else { return }
        if front {
            document.design.front.artwork = data
            if let o = Artwork.orientation(of: data) { document.design.orientation = o }
            sideSel = .front
        } else {
            document.design.back.artwork = data
            document.design.doubleSided = true
            sideSel = .back
        }
        message = "Design imported. It will be printed to the very edge of the card."
    }

    func loadCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.message = "Choose a CSV file. The first row must be column names, e.g. Name, ID, Title, Photo."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            batch = try BatchData.load(url); rowIndex = 0
            message = "Loaded \(batch.rows.count) people from \(batch.fileName). Columns: \(batch.columns.joined(separator: ", "))"
        } catch { message = "Couldn't read that file: \(error.localizedDescription)" }
    }

    func printCurrent() {
        do {
            let job = try Printer.printCard(design, fields: fields, copies: copies,
                                            title: fields["Name"].map { "ID Card – \($0)" } ?? "ID Card")
            message = "Sent to printer. \(job)"
        } catch { message = error.localizedDescription; NSSound.beep() }
    }
}

struct StatusBar: View {
    let batch: BatchData
    @Binding var rowIndex: Int
    @Binding var zoom: CGFloat
    let message: String?

    var body: some View {
        HStack(spacing: 12) {
            if !batch.rows.isEmpty {
                Button { rowIndex = max(0, rowIndex - 1) } label: { Image(systemName: "chevron.left") }.disabled(rowIndex == 0)
                Text("Card \(rowIndex + 1) of \(batch.rows.count)").monospacedDigit()
                Button { rowIndex = min(batch.rows.count - 1, rowIndex + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(rowIndex >= batch.rows.count - 1)
                Divider().frame(height: 14)
            }
            Text(message ?? "Grey area outside the card outline is bleed: colour there makes sure no white edge is left.")
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer()
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $zoom, in: 1...5).frame(width: 110)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var side: CardSide
    @Binding var selection: UUID?
    @Binding var sideSel: SideSel
    let doubleSided: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if doubleSided {
                Picker("", selection: $sideSel) { ForEach(SideSel.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().padding(10)
            } else {
                Text("Front").font(.headline).padding(10)
            }
            Text("ADD").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 6) {
                ForEach(ElementKind.allCases, id: \.self) { k in
                    Button { add(k) } label: {
                        VStack(spacing: 3) { Image(systemName: k.symbol).font(.title3); Text(k.label).font(.caption2).lineLimit(1) }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }
            }.padding(10)
            Text("LAYERS (top first)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            List(selection: $selection) {
                ForEach(side.elements.reversed()) { el in
                    Label(el.name.isEmpty ? el.kind.label : el.name, systemImage: el.kind.symbol).tag(el.id)
                }
                .onMove { from, to in
                    var rev = Array(side.elements.reversed()); rev.move(fromOffsets: from, toOffset: to)
                    side.elements = rev.reversed()
                }
                if side.artwork != nil {
                    Label("Imported design (background)", systemImage: "photo.artframe").foregroundStyle(.secondary)
                }
            }
        }
    }

    func add(_ k: ElementKind) {
        var el: CardElement
        switch k {
        case .text: el = CardElement(kind: .text, x: 20, y: 20, w: 120, h: 18, text: "Text", fontSize: 12)
        case .image:
            el = CardElement(kind: .image, x: 20, y: 20, w: 50, h: 50, fit: .fit)
            el.imageData = Artwork.pick(message: "Choose a logo or picture")
        case .photo:
            el = CardElement(kind: .photo, x: 15, y: 30, w: 64, h: 80, photoField: "Photo")
            el.imageData = Artwork.pick(message: "Choose a photo (cancel to leave an empty photo box that is filled from your data)")
        case .barcode: el = CardElement(kind: .barcode, x: 20, y: 100, w: 140, h: 26, text: "{{ID}}")
        case .qr: el = CardElement(kind: .qr, x: 20, y: 20, w: 56, h: 56, text: "{{ID}}")
        case .shape: el = CardElement(kind: .shape, x: 20, y: 20, w: 80, h: 30, fill: HexColor("#2E86DEFF"))
        }
        el.name = k.label
        side.elements.append(el)
        selection = el.id
    }
}
