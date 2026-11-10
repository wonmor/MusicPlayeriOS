import SwiftUI

// MARK: - Palette

/// Late-70s hi-fi deck: black brushed faceplate, walnut cheeks, a cyan-green
/// vacuum-fluorescent display and amber meter lamps.
enum Hifi {
    static let room = LinearGradient(colors: [Color(red: 0.07, green: 0.065, blue: 0.06),
                                              Color(red: 0.12, green: 0.11, blue: 0.10)],
                                     startPoint: .top, endPoint: .bottom)
    static let plate = Color(red: 0.115, green: 0.11, blue: 0.105)
    static let plateEdge = Color.white.opacity(0.07)
    static let walnut = LinearGradient(colors: [Color(red: 0.36, green: 0.21, blue: 0.11),
                                                Color(red: 0.25, green: 0.14, blue: 0.07),
                                                Color(red: 0.33, green: 0.19, blue: 0.10)],
                                       startPoint: .top, endPoint: .bottom)
    static let vfd = Color(red: 0.42, green: 0.96, blue: 0.86)
    static let vfdDim = Color(red: 0.42, green: 0.96, blue: 0.86).opacity(0.28)
    static let amber = Color(red: 0.98, green: 0.66, blue: 0.24)
    static let engraving = Color(red: 0.80, green: 0.78, blue: 0.74)
    static let label = Color(red: 0.96, green: 0.93, blue: 0.85)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.30)
}

// MARK: - Faceplate container

/// A section of the deck's faceplate, with walnut side cheeks.
struct Faceplate<Content: View>: View {
    var cheeks = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            if cheeks { Rectangle().fill(Hifi.walnut).frame(width: 10) }
            content
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Hifi.plate.opacity(1), Color(red: 0.09, green: 0.087, blue: 0.083)],
                                   startPoint: .top, endPoint: .bottom)
                )
            if cheeks { Rectangle().fill(Hifi.walnut).frame(width: 10) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Hifi.plateEdge, lineWidth: 1))
    }
}

/// Small engraved caption, like the silk-screened labels on a deck.
struct Engraved: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .default))
            .tracking(1.6)
            .foregroundColor(Hifi.engraving.opacity(0.75))
    }
}

// MARK: - Cassette

/// Drives reel rotation: constant tape speed past the head, so the reel with
/// less tape on it turns faster, as on a real deck.
final class ReelMotor: ObservableObject {
    var left: Double = 0
    var right: Double = 0
    private var last: Date?

    func advance(to now: Date, speed: Double, leftRadius: Double, rightRadius: Double) {
        defer { last = now }
        guard let last, speed != 0 else { return }
        let dt = min(0.1, now.timeIntervalSince(last))
        left += dt * speed / max(leftRadius, 0.05)
        right += dt * speed / max(rightRadius, 0.05)
    }
}

/// The cassette seen through the deck's door: shell, paper label with the
/// tape's name in handwriting, and the window onto the two tape packs.
struct CassetteView: View {
    let tape: Tape
    let side: TapeSide
    /// 0 at the start of the side, 1 at the end.
    let wind: Double
    /// Tape-speed units: 0 stopped, 1 playing, ±10 cueing.
    let speed: Double
    @StateObject private var motor = ReelMotor()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Shell
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .fill(LinearGradient(colors: [tape.shell.body.opacity(0.92), tape.shell.body],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

                // Paper label
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(side.rawValue)
                            .font(.system(size: h * 0.12, weight: .heavy, design: .rounded))
                            .foregroundColor(Hifi.ink.opacity(0.85))
                        Text(tape.name)
                            .font(.custom("Noteworthy-Bold", size: h * 0.095))
                            .foregroundColor(Hifi.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 4)
                        Text(tape.format.rawValue)
                            .font(.system(size: h * 0.06, weight: .bold, design: .rounded))
                            .foregroundColor(Hifi.ink.opacity(0.7))
                    }
                    .padding(.horizontal, w * 0.04)
                    .frame(height: h * 0.19)
                    Rectangle().fill(tape.shell.stripe).frame(height: h * 0.04)
                    ZStack {
                        Hifi.label
                        window(w: w, h: h)
                    }
                }
                .background(Hifi.label)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous))
                .frame(width: w * 0.88, height: h * 0.6)
                .position(x: w / 2, y: h * 0.38)

                // Head opening at the bottom edge
                Path { p in
                    p.move(to: CGPoint(x: w * 0.22, y: h))
                    p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.78))
                    p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.78))
                    p.addLine(to: CGPoint(x: w * 0.78, y: h))
                }
                .fill(Color.black.opacity(0.22))
            }
        }
        .aspectRatio(1.58, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(tape.name), \(tape.format.rawValue) cassette, side \(side.rawValue)")
    }

    private func window(w: CGFloat, h: CGFloat) -> some View {
        let ww = w * 0.62, wh = h * 0.31
        let rMin = Double(wh) * 0.22, rMax = Double(wh) * 0.47
        // Tape pack radii: area is proportional to the length of tape on each reel.
        let supply = sqrt(rMin * rMin + (1 - wind) * (rMax * rMax - rMin * rMin))
        let takeup = sqrt(rMin * rMin + wind * (rMax * rMax - rMin * rMin))
        return TimelineView(.animation(paused: speed == 0)) { ctx in
            Canvas { gc, size in
                motor.advance(to: ctx.date, speed: speed * 26, leftRadius: takeup, rightRadius: supply)
                let cy = size.height / 2
                let lx = size.width * 0.25, rx = size.width * 0.75
                // smoked window
                gc.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height * 0.45),
                        with: .color(Color.black.opacity(0.78)))
                // tape packs (side A plays right-to-left onto the left reel)
                for (x, r) in [(lx, takeup), (rx, supply)] {
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: cy - r, width: 2 * r, height: 2 * r)),
                            with: .radialGradient(Gradient(colors: [Color(red: 0.52, green: 0.33, blue: 0.19),
                                                                    Color(red: 0.36, green: 0.22, blue: 0.12)]),
                                                  center: CGPoint(x: x, y: cy), startRadius: 0, endRadius: r))
                }
                // tape between the packs
                gc.stroke(Path { p in p.move(to: CGPoint(x: lx, y: cy + takeup)); p.addLine(to: CGPoint(x: rx, y: cy + supply)) },
                          with: .color(Color(red: 0.45, green: 0.29, blue: 0.16)), lineWidth: 1.4)
                for (x, angle) in [(lx, motor.left), (rx, motor.right)] {
                    hub(gc, center: CGPoint(x: x, y: cy), radius: rMin * 0.95, angle: side == .a ? -angle : angle)
                }
            }
        }
        .frame(width: ww, height: wh)
    }

    private func hub(_ gc: GraphicsContext, center c: CGPoint, radius r: Double, angle: Double) {
        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        gc.fill(ring, with: .color(Hifi.label.opacity(0.95)))
        let inner = r * 0.55
        gc.fill(Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner)),
                with: .color(.black.opacity(0.85)))
        for k in 0..<6 {
            let a = angle + Double(k) * .pi / 3
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * inner * 0.35, y: c.y + sin(a) * inner * 0.35))
            p.addLine(to: CGPoint(x: c.x + cos(a) * inner * 1.05, y: c.y + sin(a) * inner * 1.05))
            gc.stroke(p, with: .color(Hifi.label.opacity(0.95)), lineWidth: max(1.5, r * 0.16))
        }
    }
}

/// The deck door with nothing in it.
struct EmptyDoor: View {
    var openShelf: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eject")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(Hifi.engraving.opacity(0.6))
            Text("No tape in the deck")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Hifi.engraving)
            Button(action: openShelf) {
                Label("Choose a tape", systemImage: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Hifi.amber.opacity(0.18)))
                    .foregroundColor(Hifi.amber)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.58, contentMode: .fit)
    }
}

// MARK: - Display

/// Mechanical three-digit tape counter.
struct TapeCounter: View {
    let value: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let digit = Array(String(format: "%03d", value))[i]
                Text(String(digit))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 16, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.black, Color(white: 0.16), .black],
                                                 startPoint: .top, endPoint: .bottom))
                    )
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.05)))
        .accessibilityLabel("Tape counter \(value)")
    }
}

/// Vacuum-fluorescent display: side, track, title, artist and times.
struct VFDisplay: View {
    @ObservedObject var deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                segment("SIDE \(deck.side.rawValue)", on: deck.tape != nil)
                segment(deck.tape.map { _ in "TRACK \(String(format: "%02d", deck.index + 1))/\(String(format: "%02d", deck.tracks.count))" } ?? "TRACK --/--",
                        on: deck.current != nil)
                segment(statusWord, on: true)
                Spacer(minLength: 0)
                segment(deck.autoReverse ? "AUTO REV" : "ONE SIDE", on: deck.autoReverse)
            }
            Text(deck.current?.title ?? (deck.tape == nil ? "INSERT TAPE" : "SIDE \(deck.side.rawValue) IS BLANK"))
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundColor(Hifi.vfd)
                .shadow(color: Hifi.vfd.opacity(0.7), radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack {
                Text(deck.current?.artist ?? " ")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let t = deck.current {
                    Text("\(clock(deck.position)) / \(clock(t.duration))")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(Hifi.vfd.opacity(0.8))
            // tape remaining on this side
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Hifi.vfdDim.opacity(0.4))
                    Rectangle().fill(Hifi.vfd).frame(width: g.size.width * deck.windProgress)
                        .shadow(color: Hifi.vfd.opacity(0.6), radius: 3)
                }
            }
            .frame(height: 3)
            HStack {
                Text("0").font(.system(size: 9, design: .monospaced))
                Spacer()
                Text("\(clock(deck.sideElapsed)) of \(deck.tape?.format.minutesPerSide ?? 0) min")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(Hifi.vfd.opacity(0.55))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.02, green: 0.05, blue: 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black, lineWidth: 2))
    }

    private var statusWord: String {
        switch deck.mode {
        case .playing: return "PLAY"
        case .paused: return "PAUSE"
        case .stopped: return "STOP"
        case .cueing(let f): return f ? "F.FWD" : "REWIND"
        }
    }

    private func segment(_ s: String, on: Bool) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(on ? Hifi.vfd : Hifi.vfdDim)
            .shadow(color: on ? Hifi.vfd.opacity(0.6) : .clear, radius: 2)
    }
}

/// A pair of needle VU meters lit in amber.
struct VUMeters: View {
    let active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                VUMeter(level: active ? level(t, seed: 0) : 0, channel: "L")
                VUMeter(level: active ? level(t, seed: 1.7) : 0, channel: "R")
            }
        }
    }

    /// Lively needle motion while a tape plays.
    private func level(_ t: Double, seed: Double) -> Double {
        let beat = pow(max(0, sin(t * 2 * .pi * 1.45 + seed)), 6)
        let v = 0.52 + 0.16 * sin(t * 3.1 + seed) + 0.1 * sin(t * 7.3 + seed * 2) + 0.22 * beat
        return min(1, max(0, v))
    }
}

struct VUMeter: View {
    let level: Double
    let channel: String
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            gc.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4),
                    with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.55), Hifi.amber]),
                                          startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            let pivot = CGPoint(x: w / 2, y: h * 1.25)
            let r = h * 1.05
            // scale
            for k in 0...10 {
                let f = Double(k) / 10
                let a = (-0.75 + 1.5 * f) - .pi / 2
                let p0 = CGPoint(x: pivot.x + cos(a) * r * 0.86, y: pivot.y + sin(a) * r * 0.86)
                let p1 = CGPoint(x: pivot.x + cos(a) * r * (k % 5 == 0 ? 0.74 : 0.8), y: pivot.y + sin(a) * r * (k % 5 == 0 ? 0.74 : 0.8))
                gc.stroke(Path { $0.move(to: p0); $0.addLine(to: p1) },
                          with: .color(f > 0.72 ? Color(red: 0.7, green: 0.1, blue: 0.05) : .black.opacity(0.75)), lineWidth: 1)
            }
            let a = (-0.75 + 1.5 * level) - .pi / 2
            gc.stroke(Path { p in
                p.move(to: pivot)
                p.addLine(to: CGPoint(x: pivot.x + cos(a) * r * 0.95, y: pivot.y + sin(a) * r * 0.95))
            }, with: .color(.black.opacity(0.9)), lineWidth: 1.3)
            gc.draw(Text("VU").font(.system(size: 8, weight: .bold)).foregroundColor(.black.opacity(0.7)),
                    at: CGPoint(x: w / 2, y: h * 0.72))
            gc.draw(Text(channel).font(.system(size: 8, weight: .bold)).foregroundColor(.black.opacity(0.6)),
                    at: CGPoint(x: 9, y: h - 9))
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Piano keys

/// A deck transport key: a tall key with an engraved glyph that sinks when
/// pressed and stays down (latched) while its function is active.
struct PianoKey: View {
    let glyph: String
    let caption: String
    var latched = false
    var accent: Color = Hifi.engraving
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(latched ? Hifi.amber : accent)
                Text(caption)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Hifi.engraving.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(PianoKeyStyle(latched: latched))
        .accessibilityLabel(caption.capitalized)
    }
}

struct PianoKeyStyle: ButtonStyle {
    let latched: Bool
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || latched
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: down ? [Color(white: 0.13), Color(white: 0.19)]
                                                      : [Color(white: 0.27), Color(white: 0.17)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(down ? 0.04 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(down ? 0.2 : 0.6), radius: down ? 1 : 3, y: down ? 1 : 4)
            .offset(y: down ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: down)
    }
}

struct TransportKeys: View {
    @ObservedObject var deck: Deck
    var body: some View {
        HStack(spacing: 6) {
            PianoKey(glyph: "backward.fill", caption: "REW", latched: deck.mode == .cueing(forward: false)) { deck.rewind() }
            PianoKey(glyph: deck.isPlaying ? "pause.fill" : "play.fill", caption: deck.isPlaying ? "PAUSE" : "PLAY",
                     latched: deck.isPlaying) { deck.togglePlay() }
            PianoKey(glyph: "forward.fill", caption: "F.FWD", latched: deck.mode == .cueing(forward: true)) { deck.fastForward() }
            PianoKey(glyph: "stop.fill", caption: "STOP") { deck.stop() }
            PianoKey(glyph: "arrow.left.arrow.right", caption: "FLIP") { deck.flip() }
        }
    }
}

// MARK: - Track list

struct SideList: View {
    @ObservedObject var deck: Deck
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Engraved(text: "Side \(deck.side.rawValue) running order")
                Spacer()
                if let tape = deck.tape {
                    Text("\(clock(tape.used(deck.side))) of \(tape.format.minutesPerSide):00")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Hifi.engraving.opacity(0.6))
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            if deck.tracks.isEmpty {
                Text(deck.tape == nil ? "Load a tape to see its songs." : "Nothing recorded on side \(deck.side.rawValue).")
                    .font(.system(size: 13))
                    .foregroundColor(Hifi.engraving.opacity(0.6))
                    .padding(14)
            }
            ForEach(Array(deck.tracks.enumerated()), id: \.offset) { i, t in
                Button { deck.select(i) } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", i + 1))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(i == deck.index ? Hifi.vfd : Hifi.engraving.opacity(0.5))
                            .frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(i == deck.index ? Hifi.vfd : .white.opacity(0.9))
                                .lineLimit(1)
                            Text(t.artist)
                                .font(.system(size: 11))
                                .foregroundColor(Hifi.engraving.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if i == deck.index && deck.isPlaying {
                            Image(systemName: "waveform").font(.system(size: 11)).foregroundColor(Hifi.vfd)
                        }
                        Text(clock(t.duration))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Hifi.engraving.opacity(0.6))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < deck.tracks.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.leading, 46)
                }
            }
        }
        .padding(.bottom, 6)
    }
}
