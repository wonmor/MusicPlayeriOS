import SwiftUI

// MARK: - Shelf

/// The tape shelf: every mixtape as a cassette spine. Tap to load it into
/// the deck; swipe to edit or delete; "New mixtape" starts a blank tape.
struct ShelfView: View {
    @ObservedObject var shelf: TapeShelf
    @ObservedObject var deck: Deck
    @ObservedObject var library: MusicLibrary
    var onLoad: () -> Void = {}
    @State private var editing: Tape?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if library.access != .allowed { accessCard }
                Button { editing = newTape() } label: {
                    Label("New mixtape", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Hifi.amber))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)

                Engraved(text: "\(shelf.tapes.count) tape\(shelf.tapes.count == 1 ? "" : "s") on the shelf")
                    .padding(.top, 4)

                ForEach(shelf.tapes) { tape in
                    TapeSpine(tape: tape, loaded: deck.tape?.id == tape.id)
                        .onTapGesture { deck.load(tape); onLoad() }
                        .contextMenu {
                            Button { deck.load(tape); onLoad() } label: { Label("Load into deck", systemImage: "eject") }
                            Button { editing = tape } label: { Label("Edit tape", systemImage: "pencil") }
                            Button { var copy = tape; copy.id = UUID(); copy.name += " (copy)"; copy.created = Date(); shelf.upsert(copy) } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            if tape.id != DemoTape.id {
                                Button(role: .destructive) { shelf.remove(tape) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Loads this tape into the deck")
                }
                Text("Touch and hold a tape to edit, duplicate or delete it.")
                    .font(.system(size: 11))
                    .foregroundColor(Hifi.engraving.opacity(0.5))
                    .padding(.top, 2)
            }
            .padding(16)
        }
        .sheet(item: $editing) { tape in
            TapeEditor(tape: tape, library: library) { saved in
                shelf.upsert(saved)
                deck.refresh(from: shelf.tapes)
            }
        }
    }

    private func newTape() -> Tape {
        let n = shelf.tapes.count
        return Tape(name: "Mixtape \(n)", format: .c60, shell: ShellColor.allCases[n % ShellColor.allCases.count])
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Record your own songs", systemImage: "music.note.list")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(library.access == .denied
                 ? "Music library access is off. Turn it on in Settings, iRetroMusic, Media & Apple Music to record songs from your library onto tapes."
                 : "Allow access to your music library to record its songs onto mixtapes. Until then, the Demo Tape plays three original recordings.")
                .font(.system(size: 12))
                .foregroundColor(Hifi.engraving.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if library.access == .unknown {
                Button("Allow music library access") { library.requestAccess() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Hifi.amber)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

/// A cassette seen spine-on in its case.
struct TapeSpine: View {
    let tape: Tape
    var loaded = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(tape.shell.body).frame(width: 14)
            Rectangle().fill(tape.shell.stripe).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(tape.name)
                    .font(.custom("Noteworthy-Bold", size: 18))
                    .foregroundColor(Hifi.ink)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Hifi.ink.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 6)
            Text(tape.format.rawValue)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Hifi.ink.opacity(0.75))
                .padding(.trailing, 12)
            if loaded {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Hifi.ink)
                    .padding(.trailing, 12)
                    .accessibilityLabel("In the deck")
            }
        }
        .frame(height: 58)
        .background(Hifi.label)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(loaded ? Hifi.amber : Color.black.opacity(0.3), lineWidth: loaded ? 2 : 1))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }

    private var summary: String {
        "A \(tape.sideA.count) songs | B \(tape.sideB.count) songs | \(clock(tape.used(.a) + tape.used(.b)))"
    }
}

// MARK: - Editor

/// Records a tape: name, cassette length, shell colour and the running order
/// of each side, which must fit the side's length.
struct TapeEditor: View {
    @State var tape: Tape
    @ObservedObject var library: MusicLibrary
    var onSave: (Tape) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var side: TapeSide = .a
    @State private var picking = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Tape name", text: $tape.name)
                        .font(.custom("Noteworthy-Bold", size: 20))
                    Picker("Length", selection: $tape.format) {
                        ForEach(TapeFormat.allCases) { f in Text("\(f.rawValue)  (\(f.minutesPerSide) min a side)").tag(f) }
                    }
                    shellPicker
                } header: { Text("Label") }

                Section {
                    Picker("Side", selection: $side) {
                        Text("Side A").tag(TapeSide.a)
                        Text("Side B").tag(TapeSide.b)
                    }
                    .pickerStyle(.segmented)
                    capacity
                    ForEach(tape.tracks(side)) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).lineLimit(1)
                                Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(clock(t.duration)).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in var l = tape.tracks(side); l.remove(atOffsets: idx); tape.setTracks(l, on: side) }
                    .onMove { from, to in var l = tape.tracks(side); l.move(fromOffsets: from, toOffset: to); tape.setTracks(l, on: side) }
                    Button { picking = true } label: { Label("Record songs onto side \(side.rawValue)", systemImage: "record.circle") }
                    Button { autoFill() } label: { Label("Fill the rest of side \(side.rawValue) at random", systemImage: "shuffle") }
                        .disabled(library.songs.isEmpty)
                } header: { Text("Running order") } footer: {
                    Text(note ?? "Drag to reorder, swipe to erase a song. A song is only recorded if it fits the time left on the side.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(tape.isEmpty ? "New mixtape" : "Edit tape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if tape.name.trimmingCharacters(in: .whitespaces).isEmpty { tape.name = "Untitled tape" }
                        onSave(trimmed()); dismiss()
                    }
                }
            }
            .sheet(isPresented: $picking) {
                SongPicker(tape: $tape, side: side, library: library)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Hifi.amber)
    }

    private var shellPicker: some View {
        HStack(spacing: 10) {
            Text("Shell")
            Spacer()
            ForEach(ShellColor.allCases) { c in
                Button { tape.shell = c } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.body)
                        .frame(width: 30, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(tape.shell == c ? Hifi.amber : Color.white.opacity(0.25), lineWidth: tape.shell == c ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(c.name) shell")
                .accessibilityAddTraits(tape.shell == c ? .isSelected : [])
            }
        }
    }

    private var capacity: some View {
        let used = tape.used(side), total = tape.format.sideSeconds
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3).fill(used > total ? Color.red : Hifi.amber)
                        .frame(width: g.size.width * min(1, used / total))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(clock(used)) recorded")
                Spacer()
                Text(used > total ? "\(clock(used - total)) too long" : "\(clock(total - used)) of tape left")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(used > total ? Color.red : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Fill the remaining time on this side with random songs that fit.
    private func autoFill() {
        let onTape = Set((tape.sideA + tape.sideB).map(\.id))
        var pool = library.songs.filter { !onTape.contains($0.id) }.shuffled()
        var list = tape.tracks(side)
        var left = tape.remaining(side)
        var added = 0
        while let i = pool.firstIndex(where: { $0.duration <= left }) {
            let t = pool.remove(at: i); list.append(t); left -= t.duration; added += 1
        }
        tape.setTracks(list, on: side)
        note = added == 0 ? "No more songs fit on side \(side.rawValue)." : "Recorded \(added) song\(added == 1 ? "" : "s"), \(clock(left)) of tape left."
    }

    /// If the tape was shortened, songs that no longer fit are dropped from the end.
    private func trimmed() -> Tape {
        var t = tape
        for s in [TapeSide.a, .b] {
            var l = t.tracks(s)
            while l.reduce(0, { $0 + $1.duration }) > t.format.sideSeconds + 0.5, !l.isEmpty { l.removeLast() }
            t.setTracks(l, on: s)
        }
        return t
    }
}

/// Chooses songs to record onto one side.
struct SongPicker: View {
    @Binding var tape: Tape
    let side: TapeSide
    @ObservedObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(clock(tape.remaining(side))) left on side \(side.rawValue)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Hifi.amber)
                }
                if library.access != .allowed {
                    Section {
                        Text("Allow music library access to record your own songs.")
                        if library.access == .unknown { Button("Allow access") { library.requestAccess() } }
                    }
                } else if library.loaded && library.songs.isEmpty {
                    Section { Text("There are no songs in this iPhone's music library yet. Songs you add in the Music app appear here.") }
                }
                if !filtered(library.songs).isEmpty {
                    Section("Your library") { ForEach(filtered(library.songs)) { row($0) } }
                }
                Section("Demo recordings") { ForEach(filtered(DemoTape.tracks)) { row($0) } }
            }
            .searchable(text: $query, prompt: "Songs or artists")
            .navigationTitle("Record onto side \(side.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .tint(Hifi.amber)
    }

    private func filtered(_ l: [Track]) -> [Track] {
        guard !query.isEmpty else { return l }
        return l.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
    }

    private func row(_ t: Track) -> some View {
        let onSide = tape.tracks(side).contains { $0.id == t.id }
        let fits = tape.fits(t, on: side)
        return Button {
            guard !onSide, fits else { return }
            var l = tape.tracks(side); l.append(t); tape.setTracks(l, on: side)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).foregroundStyle(.primary).lineLimit(1)
                    Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(clock(t.duration)).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                Image(systemName: onSide ? "checkmark" : (fits ? "plus" : "nosign"))
                    .foregroundStyle(onSide ? Hifi.vfd : (fits ? Hifi.amber : .secondary))
                    .frame(width: 22)
            }
        }
        .disabled(!fits && !onSide)
        .accessibilityHint(onSide ? "Already on this side" : (fits ? "Records this song" : "Doesn't fit the time left"))
    }
}
