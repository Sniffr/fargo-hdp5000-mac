import SwiftUI
import AppKit

@main
struct IDStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        DocumentGroup(newDocument: NewDoc.make()) { file in
            EditorView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Blank Card") { NewDoc.open(Templates.blank) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Print a Ready-Made Design…") { NewDoc.openArtwork() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings { PrinterSettingsView().frame(width: 520) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.activate(ignoringOtherApps: true) }
}

/// Opens new untitled documents from code (File menu helpers).
enum NewDoc {
    nonisolated(unsafe) static var pending: CardDesign? = nil

    static func make() -> CardDocument {
        defer { pending = nil }
        return CardDocument(design: pending ?? Templates.employee)
    }

    static func open(_ design: CardDesign) {
        pending = design
        NSDocumentController.shared.newDocument(nil)
    }

    /// Pick image/PDF files made in another app (front, optionally back) and open them as a card.
    static func openArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Artwork.types
        panel.allowsMultipleSelection = true
        panel.message = "Choose your card design. Pick two files to print front and back."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var d = Templates.blank
        d.prefs.sharpBlack = false
        guard let front = try? Data(contentsOf: urls[0]) else { return }
        d.front.artwork = front
        d.orientation = Artwork.orientation(of: front) ?? .landscape
        if urls.count > 1, let back = try? Data(contentsOf: urls[1]) {
            d.back.artwork = back; d.doubleSided = true
        }
        open(d)
    }
}
