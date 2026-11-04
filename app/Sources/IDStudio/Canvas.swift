import SwiftUI

/// The card preview with click-to-select, drag-to-move and a resize handle.
struct CanvasView: View {
    @Binding var side: CardSide
    @Binding var selection: UUID?
    let orientation: Orientation
    let fields: [String: String]
    let zoom: CGFloat

    @State private var dragStart: CGRect? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let bleed = orientation.bleed
        let trim = orientation.trim
        let o = orientation.trimOrigin
        let size = CGSize(width: bleed.width * zoom, height: bleed.height * zoom)

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                if let img = Renderer.preview(side, orientation: orientation, fields: fields, scale: zoom * displayScale) {
                    Image(decorative: img, scale: displayScale).resizable().frame(width: size.width, height: size.height)
                }
                // Bleed: shaded, it is printed but falls off the card edge.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRoundedRect(in: CGRect(x: o.x * zoom, y: o.y * zoom, width: trim.width * zoom, height: trim.height * zoom),
                                     cornerSize: CGSize(width: Geo.cornerRadius * zoom, height: Geo.cornerRadius * zoom))
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                // Card edge and safe area
                RoundedRectangle(cornerRadius: Geo.cornerRadius * zoom)
                    .stroke(Color.primary.opacity(0.7), lineWidth: 1)
                    .frame(width: trim.width * zoom, height: trim.height * zoom)
                    .offset(x: o.x * zoom, y: o.y * zoom)
                    .allowsHitTesting(false)
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
                    .frame(width: (trim.width - 2 * Geo.safeInset) * zoom, height: (trim.height - 2 * Geo.safeInset) * zoom)
                    .offset(x: (o.x + Geo.safeInset) * zoom, y: (o.y + Geo.safeInset) * zoom)
                    .allowsHitTesting(false)

                if let sel = side.elements.first(where: { $0.id == selection }) {
                    selectionBox(sel, origin: o)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(moveGesture(origin: o))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(40)
        }
    }

    func cardPoint(_ p: CGPoint, origin o: CGPoint) -> CGPoint { CGPoint(x: p.x / zoom - o.x, y: p.y / zoom - o.y) }

    func hit(_ p: CGPoint) -> UUID? {
        side.elements.last(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(p) })?.id
    }

    func moveGesture(origin o: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStart == nil {
                    let p = cardPoint(g.startLocation, origin: o)
                    // Keep the current selection when grabbing inside it, so a
                    // selected element under another one can still be moved.
                    if let s = selection, let el = side.elements.first(where: { $0.id == s }), el.frame.insetBy(dx: -2, dy: -2).contains(p) {
                    } else { selection = hit(p) }
                    dragStart = side.elements.first(where: { $0.id == selection })?.frame ?? .null
                }
                guard let start = dragStart, !start.isNull, let i = side.elements.firstIndex(where: { $0.id == selection }) else { return }
                var dx = g.translation.width / zoom, dy = g.translation.height / zoom
                if NSEvent.modifierFlags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
                side.elements[i].x = (start.minX + dx).rounded(toPlaces: 1)
                side.elements[i].y = (start.minY + dy).rounded(toPlaces: 1)
            }
            .onEnded { _ in dragStart = nil }
    }

    @ViewBuilder func selectionBox(_ el: CardElement, origin o: CGPoint) -> some View {
        let r = CGRect(x: (el.x + o.x) * zoom, y: (el.y + o.y) * zoom, width: el.w * zoom, height: el.h * zoom)
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: r.width, height: r.height)
            .rotationEffect(.degrees(el.rotation))
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
        Circle()
            .fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .offset(x: r.maxX - 5.5, y: r.maxY - 5.5)
            .gesture(resizeGesture(el.id))
            .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
    }

    func resizeGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard let i = side.elements.firstIndex(where: { $0.id == id }) else { return }
                if dragStart == nil { dragStart = side.elements[i].frame }
                guard let s = dragStart else { return }
                var w = max(4, s.width + g.translation.width / zoom), h = max(4, s.height + g.translation.height / zoom)
                // QR codes and photos keep their proportions; hold Shift for any element.
                let kind = side.elements[i].kind
                if kind == .qr || NSEvent.modifierFlags.contains(.shift) { let k = max(w / s.width, h / s.height); w = s.width * k; h = s.height * k }
                side.elements[i].w = w.rounded(toPlaces: 1); side.elements[i].h = h.rounded(toPlaces: 1)
            }
            .onEnded { _ in dragStart = nil }
    }
}

extension CGFloat {
    func rounded(toPlaces p: Int) -> CGFloat { let m = pow(10, CGFloat(p)); return (self * m).rounded() / m }
}
