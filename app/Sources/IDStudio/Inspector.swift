import SwiftUI
import AppKit

struct Inspector: View {
    @Binding var document: CardDocument
    @Binding var side: CardSide
    @Binding var selection: UUID?
    let columns: [String]

    var body: some View {
        Form {
            if let i = side.elements.firstIndex(where: { $0.id == selection }) {
                ElementInspector(el: $side.elements[i], columns: columns,
                                 forward: { move(i, to: side.elements.count - 1) }, backward: { move(i, to: 0) },
                                 duplicate: { duplicate(i) }, delete: { side.elements.remove(at: i); selection = nil })
            } else {
                cardSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder var cardSection: some View {
        Section("Card") {
            Toggle("Print both sides", isOn: $document.design.doubleSided)
            ColorPicker("Background", selection: color($side.background))
            if side.artwork != nil {
                Picker("Imported design", selection: $side.artworkFit) {
                    Text("Fill to edge (crops 1–2 mm)").tag(ImageFit.fill)
                    Text("Fit on card (nothing cut off)").tag(ImageFit.fit)
                    Text("Stretch to edge").tag(ImageFit.stretch)
                }
                HStack {
                    Text("Size")
                    Slider(value: opt($side.artworkScale, 100), in: 80...110, step: 0.5)
                    Text(String(format: "%.1f%%", side.artworkScale ?? 100)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Stepper(String(format: "Move right/left: %+.1f mm", side.artworkOffsetX ?? 0),
                        value: opt($side.artworkOffsetX, 0), in: -5...5, step: 0.1)
                Stepper(String(format: "Move down/up: %+.1f mm", side.artworkOffsetY ?? 0),
                        value: opt($side.artworkOffsetY, 0), in: -5...5, step: 0.1)
                HStack {
                    Button("Match background to design") {
                        if let d = side.artwork, let img = Renderer.cgImage(from: d), let c = Renderer.cornerColor(img) { side.background = c }
                    }
                    .help("Colour the area around a shrunk design like the design's own edges, so no border shows")
                    Button("Reset") { side.artworkScale = nil; side.artworkOffsetX = nil; side.artworkOffsetY = nil }
                }
                Text("Shrink the design until nothing important touches the card outline. The space around it prints in the background colour.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Remove imported design", role: .destructive) { side.artwork = nil }
            }
        }
        Section("Ribbon") {
            Picker("Ribbon", selection: $document.design.prefs.ribbon) {
                Text("YMCK (colour + black)").tag("YMCK")
                Text("YMC (colour only)").tag("YMC")
                Text("YMCKK").tag("YMCKK")
                Text("YMCKH").tag("YMCKH")
                Text("Premium resin (black only)").tag("PremiumResin")
            }
            Toggle("Sharp black text & barcodes", isOn: $document.design.prefs.sharpBlack)
                .disabled(document.design.prefs.ribbon == "YMC")
            Text("Pure-black text and barcodes print with the black resin panel, so they scan reliably. Turn off for photo-heavy designs to keep HID's colour correction.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Film", selection: $document.design.prefs.film) {
                Text("Clear").tag("Clear"); Text("Holographic").tag("Holo")
            }
            Toggle("Card comes out upside down", isOn: $document.design.prefs.flip180)
            if document.design.doubleSided {
                Toggle("Back comes out upside down", isOn: $document.design.prefs.flipBack)
            }
        }
        Section {
            Text("Click an item on the card to edit it. Type {{Column}} in any text, barcode or QR to fill it from your data, e.g. {{Name}}.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func move(_ i: Int, to j: Int) {
        let el = side.elements.remove(at: i); side.elements.insert(el, at: j)
    }
    func duplicate(_ i: Int) {
        var el = side.elements[i]; el.id = UUID(); el.x += 6; el.y += 6
        side.elements.insert(el, at: i + 1); selection = el.id
    }
}

func opt(_ b: Binding<Double?>, _ fallback: Double) -> Binding<Double> {
    Binding(get: { b.wrappedValue ?? fallback }, set: { b.wrappedValue = $0 })
}

func dbl(_ b: Binding<CGFloat>) -> Binding<Double> {
    Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = CGFloat($0) })
}

func color(_ b: Binding<HexColor>) -> Binding<CGColor> {
    Binding(get: { b.wrappedValue.cg }, set: { b.wrappedValue = HexColor(cg: $0) })
}

struct ElementInspector: View {
    @Binding var el: CardElement
    let columns: [String]
    let forward: () -> Void, backward: () -> Void, duplicate: () -> Void, delete: () -> Void

    static let fonts: [String] = ["Helvetica Neue", "Helvetica", "Arial", "Avenir Next", "Futura", "Gill Sans", "Optima",
                                  "Georgia", "Times New Roman", "Palatino", "Menlo", "Courier New", "Verdana", "Trebuchet MS"]

    var body: some View {
        Section(el.kind.label) {
            TextField("Name", text: $el.name)
            HStack { num("X", $el.x); num("Y", $el.y) }
            HStack { num("W", $el.w); num("H", $el.h) }
            HStack {
                Text("Rotate")
                Slider(value: $el.rotation, in: -180...180, step: 1)
                Text("\(Int(el.rotation))°").monospacedDigit().frame(width: 36)
            }
            Text("Sizes are in points (72 per inch). The card is \(Int(Geo.trimLong)) × \(Int(Geo.trimShort)).")
                .font(.caption).foregroundStyle(.secondary)
        }
        switch el.kind {
        case .text: textSection
        case .barcode, .qr: codeSection
        case .image, .photo: imageSection
        case .shape: EmptyView()
        }
        shapeSection
        Section {
            HStack {
                Button("Bring to Front", action: forward)
                Button("Send to Back", action: backward)
            }
            HStack {
                Button("Duplicate", action: duplicate)
                Button("Delete", role: .destructive, action: delete)
            }
        }
    }

    func num(_ label: String, _ v: Binding<CGFloat>) -> some View {
        TextField(label, value: dbl(v), format: .number.precision(.fractionLength(0...1)))
    }

    var fieldMenu: some View {
        Menu("Insert data field") {
            let cols = columns.isEmpty ? Array(Templates.sampleFields.keys).sorted() : columns
            ForEach(cols, id: \.self) { c in Button(c) { el.text += "{{\(c)}}" } }
        }
    }

    @ViewBuilder var textSection: some View {
        Section("Text") {
            TextField("Text", text: $el.text, axis: .vertical).lineLimit(1...5)
            fieldMenu
            Picker("Font", selection: $el.fontName) { ForEach(Self.fonts, id: \.self) { Text($0).tag($0) } }
            HStack {
                TextField("Size", value: dbl($el.fontSize), format: .number.precision(.fractionLength(0...1)))
                Toggle("B", isOn: $el.bold).toggleStyle(.button).bold()
                Toggle("I", isOn: $el.italic).toggleStyle(.button).italic()
            }
            Picker("Align", selection: $el.align) {
                Image(systemName: "text.alignleft").tag(TextAlign.left)
                Image(systemName: "text.aligncenter").tag(TextAlign.center)
                Image(systemName: "text.alignright").tag(TextAlign.right)
            }.pickerStyle(.segmented)
            ColorPicker("Colour", selection: color($el.color))
            Toggle("Shrink long text to fit", isOn: $el.shrinkToFit)
        }
    }

    @ViewBuilder var codeSection: some View {
        Section(el.kind == .qr ? "QR code" : "Barcode (Code 128)") {
            TextField("Value", text: $el.text)
            fieldMenu
            ColorPicker("Colour", selection: color($el.color))
            if el.kind == .barcode {
                Text("Keep barcodes black on a light background so scanners read them.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var imageSection: some View {
        Section(el.kind == .photo ? "Photo" : "Image") {
            HStack {
                Button(el.imageData == nil ? "Choose Picture…" : "Replace Picture…") {
                    if let d = Artwork.pick(message: "Choose a picture") { el.imageData = d }
                }
                if el.imageData != nil { Button("Remove") { el.imageData = nil } }
            }
            Picker("Fit", selection: $el.fit) { ForEach(ImageFit.allCases) { Text($0.label).tag($0) } }
            if el.kind == .photo {
                Picker("Photo from data column", selection: $el.photoField) {
                    Text("None").tag("")
                    ForEach(Array(Set(columns + [el.photoField]).filter { !$0.isEmpty }).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Text("When printing from a spreadsheet, this column holds each person's photo file (a full path, or a file name in the same folder as the CSV).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var shapeSection: some View {
        Section(el.kind == .shape ? "Shape" : "Box") {
            ColorPicker("Fill", selection: color($el.fill))
            ColorPicker("Border", selection: color($el.stroke))
            HStack {
                TextField("Border width", value: dbl($el.strokeWidth), format: .number.precision(.fractionLength(0...1)))
                TextField("Corner radius", value: dbl($el.cornerRadius), format: .number.precision(.fractionLength(0...1)))
            }
            if el.kind == .shape || el.kind == .photo || el.kind == .image { Toggle("Oval", isOn: $el.ellipse) }
            if el.kind == .shape {
                Button("Stretch across card edges (no white edge)") {
                    el.x = -Geo.pageLong; el.w = Geo.pageLong * 3
                }
                .help("Extends the shape past the card edge into the bleed so it prints right to the edge")
            }
        }
    }
}
