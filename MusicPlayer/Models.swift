import Foundation
import SwiftUI

// MARK: - Track

/// One song that can be recorded onto a tape.
struct Track: Identifiable, Codable, Hashable {
    enum Source: Codable, Hashable {
        /// A song in the user's music library (MPMediaItem persistent ID).
        case library(UInt64)
        /// One of the original demo-tape recordings bundled with the app.
        case demo(String)
        /// Screenshot / preview data only; release builds never create it.
        case sample
    }

    var id: String
    var title: String
    var artist: String
    var duration: TimeInterval
    var source: Source

    var isDemo: Bool { if case .demo = source { return true } else { return false } }
}

// MARK: - Tape formats and shells

/// Cassette lengths. The number is the total running time; each side holds half.
enum TapeFormat: String, Codable, CaseIterable, Identifiable {
    case c10 = "C10", c46 = "C46", c60 = "C60", c90 = "C90"
    var id: String { rawValue }
    /// Running time of one side, in seconds.
    var sideSeconds: TimeInterval {
        switch self {
        case .c10: return 5 * 60
        case .c46: return 23 * 60
        case .c60: return 30 * 60
        case .c90: return 45 * 60
        }
    }
    var minutesPerSide: Int { Int(sideSeconds / 60) }
}

/// Cassette shell colours.
enum ShellColor: String, Codable, CaseIterable, Identifiable {
    case smoke, tangerine, teal, ivory, oxblood, cobalt
    var id: String { rawValue }
    var body: Color {
        switch self {
        case .smoke:     return Color(red: 0.22, green: 0.22, blue: 0.23)
        case .tangerine: return Color(red: 0.93, green: 0.47, blue: 0.16)
        case .teal:      return Color(red: 0.10, green: 0.50, blue: 0.52)
        case .ivory:     return Color(red: 0.86, green: 0.82, blue: 0.72)
        case .oxblood:   return Color(red: 0.50, green: 0.13, blue: 0.14)
        case .cobalt:    return Color(red: 0.17, green: 0.30, blue: 0.64)
        }
    }
    /// Stripe colour across the paper label.
    var stripe: Color {
        switch self {
        case .ivory:     return Color(red: 0.85, green: 0.30, blue: 0.18)
        case .tangerine: return Color(red: 0.18, green: 0.18, blue: 0.20)
        default:         return Color(red: 0.95, green: 0.55, blue: 0.18)
        }
    }
    var name: String { rawValue.capitalized }
}

enum TapeSide: String, Codable {
    case a = "A", b = "B"
    var flipped: TapeSide { self == .a ? .b : .a }
}

// MARK: - Tape

/// A mixtape: two sides of songs that must fit the cassette's running time.
struct Tape: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var format: TapeFormat
    var shell: ShellColor
    var sideA: [Track] = []
    var sideB: [Track] = []
    var created = Date()

    func tracks(_ side: TapeSide) -> [Track] { side == .a ? sideA : sideB }
    func used(_ side: TapeSide) -> TimeInterval { tracks(side).reduce(0) { $0 + $1.duration } }
    func remaining(_ side: TapeSide) -> TimeInterval { max(0, format.sideSeconds - used(side)) }
    func fits(_ track: Track, on side: TapeSide) -> Bool { track.duration <= remaining(side) + 0.5 }
    var isEmpty: Bool { sideA.isEmpty && sideB.isEmpty }
    var trackCount: Int { sideA.count + sideB.count }

    mutating func setTracks(_ tracks: [Track], on side: TapeSide) {
        if side == .a { sideA = tracks } else { sideB = tracks }
    }
}

// MARK: - Shelf (persistence)

/// The user's tapes, saved as JSON in the app's documents folder.
@MainActor
final class TapeShelf: ObservableObject {
    @Published var tapes: [Tape] = [] { didSet { save() } }
    private let url: URL
    private var persist = false

    init(fileName: String = "shelf.json") {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Tape].self, from: data) {
            tapes = saved
        }
        if !tapes.contains(where: { $0.id == DemoTape.id }) {
            tapes.insert(DemoTape.tape, at: 0)
        }
        persist = true
    }

    func tape(_ id: UUID?) -> Tape? { tapes.first { $0.id == id } }

    func upsert(_ tape: Tape) {
        if let i = tapes.firstIndex(where: { $0.id == tape.id }) { tapes[i] = tape } else { tapes.append(tape) }
    }

    func remove(_ tape: Tape) { tapes.removeAll { $0.id == tape.id } }

    private func save() {
        guard persist, let data = try? JSONEncoder().encode(tapes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Screenshot data: replaces the shelf in memory without touching disk.
    func loadSamples(_ samples: [Tape]) {
        persist = false
        tapes = samples
    }
}

// MARK: - Demo tape

/// The tape every new install starts with: three short original
/// instrumentals made for iRetroMusic (scripts/demotape.py), so the deck
/// plays something before the user has recorded a tape of their own.
enum DemoTape {
    static let id = UUID(uuidString: "6E2D1A30-0C41-4B7E-9A2F-1D1E5A7C0F01")!
    static let artist = "iRetroMusic House Band"
    static let tracks: [Track] = [
        Track(id: "demo-1-side-street", title: "Side Street", artist: artist, duration: 47.7, source: .demo("demo-1-side-street")),
        Track(id: "demo-2-night-bus", title: "Night Bus", artist: artist, duration: 42.0, source: .demo("demo-2-night-bus")),
        Track(id: "demo-3-last-light", title: "Last Light", artist: artist, duration: 48.7, source: .demo("demo-3-last-light")),
    ]
    static var tape: Tape {
        Tape(id: id, name: "Demo Tape", format: .c10, shell: .tangerine,
             sideA: [tracks[0], tracks[1]], sideB: [tracks[2]], created: .distantPast)
    }
}

/// "m:ss" for track and side times.
func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}
