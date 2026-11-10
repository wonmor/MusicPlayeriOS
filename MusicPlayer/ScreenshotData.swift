import Foundation

/// Store-screenshot fixtures. Active only in Debug builds launched with
/// `-ui-shot <deck|shelf|about|demo>`; release builds never use them.
enum ScreenshotData {
    enum Shot { case deck, shelf, about, demo }

    @MainActor
    static func apply(shelf: TapeShelf, deck: Deck, library: MusicLibrary) -> Shot? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ui-shot"), i + 1 < args.count else { return nil }
        library.loadSamples(songs)
        let tapes = sampleTapes
        shelf.loadSamples([DemoTape.tape] + tapes)
        switch args[i + 1] {
        case "demo":
            deck.stage(DemoTape.tape, side: .a, index: 1, position: 17, playing: true)
            return .demo
        case "shelf":
            deck.stage(tapes[0], side: .a, index: 3, position: 71, playing: true)
            return .shelf
        case "about":
            deck.stage(tapes[0], side: .a, index: 3, position: 71, playing: false)
            return .about
        case "sideb":
            deck.stage(tapes[1], side: .b, index: 2, position: 140, playing: true)
            return .deck
        default:
            deck.stage(tapes[0], side: .a, index: 3, position: 71, playing: true)
            return .deck
        }
        #else
        return nil
        #endif
    }

    /// Invented songs and artists for screenshots.
    static let songs: [Track] = {
        let raw: [(String, String, Double)] = [
            ("Paper Planes Over Elm Street", "The Weekday Club", 214), ("Rooftop Antenna", "Marlow & The Static", 187),
            ("Summer Job", "Juniper Lane", 243), ("Highway 9 at Dusk", "The Weekday Club", 266),
            ("Walkie-Talkie", "Polly Ostrander", 172), ("Glow Stick Heart", "Neon Paperback", 205),
            ("Late Bus Home", "Juniper Lane", 231), ("Corner Store Cola", "Marlow & The Static", 158),
            ("Rewind the Reel", "Polly Ostrander", 222), ("Quiet Kitchen Radio", "Ferris Wheel Society", 249),
            ("Postcard From Nowhere", "Neon Paperback", 198), ("Basement Show", "The Weekday Club", 181),
            ("Polaroid Weather", "Ferris Wheel Society", 237), ("Static on Channel 3", "Marlow & The Static", 209),
            ("Lights Out, Headphones On", "Juniper Lane", 276), ("Kite String", "Polly Ostrander", 190),
        ]
        return raw.enumerated().map { i, r in Track(id: "sample-\(i)", title: r.0, artist: r.1, duration: r.2, source: .sample) }
    }()

    static var sampleTapes: [Tape] {
        let s = songs
        return [
            Tape(name: "Road Trip '98", format: .c60, shell: .teal,
                 sideA: [s[3], s[1], s[6], s[0], s[8], s[12], s[4]], sideB: [s[9], s[13], s[2], s[15], s[7]]),
            Tape(name: "Rainy Sunday", format: .c46, shell: .ivory,
                 sideA: [s[9], s[12], s[14], s[10]], sideB: [s[4], s[15], s[2], s[6]]),
            Tape(name: "Gym Class Hits", format: .c90, shell: .oxblood,
                 sideA: [s[5], s[11], s[13], s[1], s[7], s[0]], sideB: [s[3], s[8], s[10]]),
            Tape(name: "For Sam", format: .c60, shell: .cobalt,
                 sideA: [s[0], s[14], s[2]], sideB: []),
        ]
    }
}
