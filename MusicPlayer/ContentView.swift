import SwiftUI

/// iRetroMusic: a mixtape deck. Record songs from your library onto
/// cassettes that have a real running time per side, then play them on a
/// hi-fi tape deck with a tape counter, auto-reverse and piano-key transport.
struct ContentView: View {
    @StateObject private var shelf = TapeShelf()
    @StateObject private var deck = Deck()
    @StateObject private var library = MusicLibrary()
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showShelf = false
    @State private var showAbout = false

    var body: some View {
        ZStack {
            Hifi.room.ignoresSafeArea()
            if hSize == .regular {
                wideLayout
            } else {
                ScrollView { deckColumn.padding(.horizontal, 14).padding(.bottom, 20) }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShelf) {
            NavigationStack {
                ShelfView(shelf: shelf, deck: deck, library: library) { showShelf = false }
                    .background(Hifi.room.ignoresSafeArea())
                    .navigationTitle("Tape shelf")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showShelf = false } } }
            }
            .preferredColorScheme(.dark)
            .tint(Hifi.amber)
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .alert("Deck", isPresented: Binding(get: { deck.message != nil }, set: { if !$0 { deck.message = nil } })) {
            Button("OK", role: .cancel) { deck.message = nil }
        } message: { Text(deck.message ?? "") }
        .onChange(of: shelf.tapes) { _, tapes in deck.refresh(from: tapes) }
        .task {
            if let shot = ScreenshotData.apply(shelf: shelf, deck: deck, library: library) {
                showShelf = shot == .shelf
                showAbout = shot == .about
                return
            }
            if deck.tape == nil, let first = shelf.tapes.first { deck.load(first) }
            if library.access == .allowed { library.load() }
        }
    }

    // MARK: Layouts

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("iRetroMusic")
                    .font(.system(size: 20, weight: .black, design: .default))
                    .italic()
                    .foregroundColor(Hifi.engraving)
                Text("STEREO CASSETTE DECK  |  AUTO REVERSE")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(Hifi.engraving.opacity(0.5))
            }
            Spacer()
            if hSize != .regular {
                headerButton("square.stack.3d.up", "Tape shelf") { showShelf = true }
            }
            headerButton("info.circle", "About iRetroMusic") { showAbout = true }
        }
        .padding(.top, 6)
    }

    private func headerButton(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Hifi.engraving)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
        .accessibilityLabel(label)
    }

    private var deckColumn: some View {
        VStack(spacing: 12) {
            header
            Faceplate {
                VStack(spacing: 12) {
                    HStack {
                        Engraved(text: "Cassette compartment")
                        Spacer()
                        if deck.tape != nil {
                            Button { deck.eject() } label: {
                                Label("EJECT", systemImage: "eject.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Hifi.engraving.opacity(0.8))
                            }
                            .accessibilityLabel("Eject tape")
                        }
                    }
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55))
                        if let tape = deck.tape {
                            CassetteView(tape: tape, side: deck.side, wind: deck.windProgress, speed: reelSpeed)
                                .padding(14)
                                .id(tape.id.uuidString + deck.side.rawValue)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            EmptyDoor { showShelf = true }.padding(14)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: deck.tape?.id)
                    HStack(alignment: .center, spacing: 10) {
                        VUMeters(active: deck.isPlaying)
                        VStack(spacing: 3) {
                            TapeCounter(value: deck.counter)
                            Engraved(text: "Counter")
                        }
                    }
                }
                .padding(14)
            }
            VFDisplay(deck: deck)
            TransportKeys(deck: deck)
                .padding(.vertical, 4)
            Toggle(isOn: $deck.autoReverse) {
                Label("Auto reverse: play side B after side A", systemImage: "arrow.uturn.down")
                    .font(.system(size: 12))
                    .foregroundColor(Hifi.engraving.opacity(0.8))
            }
            .tint(Hifi.amber)
            .padding(.horizontal, 4)
            if hSize != .regular {
                Faceplate(cheeks: false) { SideList(deck: deck) }
            }
        }
        .frame(maxWidth: 620)
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView { deckColumn.padding(.bottom, 20) }
                .frame(maxWidth: 560)
            VStack(spacing: 12) {
                Faceplate(cheeks: false) { ScrollView { SideList(deck: deck) } }
                    .frame(maxHeight: 360)
                Faceplate(cheeks: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Engraved(text: "Tape shelf").padding([.horizontal, .top], 16)
                        ShelfView(shelf: shelf, deck: deck, library: library)
                    }
                }
            }
            .padding(.top, 60)
        }
        .padding(.horizontal, 24)
    }

    private var reelSpeed: Double {
        switch deck.mode {
        case .playing: return 1
        case .cueing(let f): return f ? 12 : -12
        default: return 0
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iRetroMusic turns your music library into mixtapes. Pick a cassette length, record songs onto side A and side B until the tape is full, write the label, then play it on the deck: the counter turns, the tape moves from one reel to the other, and auto-reverse flips to side B when side A runs out.")
                        .font(.callout)
                }
                Section("How it works") {
                    row("record.circle", "Record", "Each side holds half the cassette's running time: C46, C60 or C90. A song is only recorded if it fits.")
                    row("square.stack.3d.up", "Shelf", "Every tape you make is kept on the shelf. Touch and hold a tape to edit, duplicate or delete it.")
                    row("arrow.left.arrow.right", "Flip", "FLIP turns the tape over. Auto reverse does it for you at the end of side A.")
                    row("music.note", "Demo Tape", "Three short original instrumentals made for iRetroMusic, so the deck plays something before you record your first tape.")
                }
                Section("Privacy") {
                    Text("iRetroMusic reads your music library only to list and play songs on this device. It has no account, no ads and no analytics, and sends nothing anywhere.")
                        .font(.footnote)
                    Link("Privacy Policy", destination: URL(string: "https://wonmor.github.io/MusicPlayeriOS/privacy.html")!)
                    Link("Support", destination: URL(string: "https://wonmor.github.io/MusicPlayeriOS/support.html")!)
                    Link("john@orchestrsim.com", destination: URL(string: "mailto:john@orchestrsim.com")!)
                }
                Section {
                    LabeledContent("Version", value: version)
                    LabeledContent("Made by", value: "John Seong, Orch Aerospace, Inc.")
                }
            }
            .navigationTitle("About iRetroMusic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .tint(Hifi.amber)
    }

    private func row(_ glyph: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph).foregroundColor(Hifi.amber).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
