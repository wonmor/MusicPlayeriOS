import Foundation
import MediaPlayer
import AVFoundation
import Combine
import UIKit

// MARK: - Music library

/// Reads songs from the user's music library (the Music app) so they can be
/// recorded onto tapes. Nothing leaves the device.
@MainActor
final class MusicLibrary: ObservableObject {
    enum Access { case unknown, allowed, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var songs: [Track] = []
    @Published private(set) var loaded = false

    init() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: access = .allowed
        case .denied, .restricted: access = .denied
        default: access = .unknown
        }
    }

    func requestAccess() {
        MPMediaLibrary.requestAuthorization { status in
            Task { @MainActor in
                self.access = (status == .authorized) ? .allowed : .denied
                if self.access == .allowed { self.load() }
            }
        }
    }

    func load() {
        guard access == .allowed else { loaded = true; return }
        Task.detached(priority: .userInitiated) {
            let items = MPMediaQuery.songs().items ?? []
            let tracks: [Track] = items.compactMap { item in
                guard item.playbackDuration > 1 else { return nil }
                return Track(id: "lib-\(item.persistentID)",
                             title: item.title ?? "Untitled",
                             artist: item.artist ?? "Unknown artist",
                             duration: item.playbackDuration,
                             source: .library(item.persistentID))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            await MainActor.run {
                self.songs = tracks
                self.loaded = true
            }
        }
    }

    /// Screenshot data only.
    func loadSamples(_ tracks: [Track]) {
        access = .allowed
        songs = tracks
        loaded = true
    }

    static func mediaItem(_ id: UInt64) -> MPMediaItem? {
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: id),
                                                      forProperty: MPMediaItemPropertyPersistentID))
        return q.items?.first
    }
}

// MARK: - Deck

/// The tape deck: plays one side of the loaded tape in order, keeps a tape
/// counter, flips (auto-reverse) at the end of side A, and stops at the end
/// of side B. Library songs play through the system music player; the demo
/// tape plays its bundled recordings.
@MainActor
final class Deck: ObservableObject {
    enum Mode: Equatable { case stopped, playing, paused, cueing(forward: Bool) }

    @Published private(set) var tape: Tape?
    @Published private(set) var side: TapeSide = .a
    @Published private(set) var index: Int = 0
    @Published private(set) var mode: Mode = .stopped
    /// Seconds into the current track.
    @Published private(set) var position: TimeInterval = 0
    @Published var autoReverse = true
    @Published var message: String?

    private let system = MPMusicPlayerController.applicationQueuePlayer
    private var demo: AVAudioPlayer?
    private var ticker: AnyCancellable?
    private var sawPlaying = false
    private let thunk = UIImpactFeedbackGenerator(style: .rigid)
    private var simulated = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    // MARK: State

    var tracks: [Track] { tape?.tracks(side) ?? [] }
    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var isPlaying: Bool { mode == .playing }

    /// Seconds of tape that have passed the head on this side.
    var sideElapsed: TimeInterval {
        tracks.prefix(index).reduce(0) { $0 + $1.duration } + position
    }
    var sideLength: TimeInterval { tape?.format.sideSeconds ?? TapeFormat.c60.sideSeconds }
    /// 0 at the start of the side, 1 at its physical end.
    var windProgress: Double { min(1, max(0, sideElapsed / sideLength)) }
    /// Mechanical counter reading (000 to 999), like a three-digit deck counter.
    var counter: Int { Int(sideElapsed / 1.5) % 1000 }

    // MARK: Transport

    func load(_ tape: Tape) {
        stopAudio()
        self.tape = tape
        side = .a
        index = 0
        position = 0
        mode = .stopped
        thunk.impactOccurred()
    }

    func eject() {
        stopAudio()
        tape = nil
        mode = .stopped
        position = 0
        index = 0
        thunk.impactOccurred()
    }

    /// Keeps the loaded tape in sync after it was edited on the shelf.
    func refresh(from shelf: [Tape]) {
        guard let t = tape else { return }
        guard let fresh = shelf.first(where: { $0.id == t.id }) else { eject(); return }
        if fresh != t {
            tape = fresh
            if index >= tracks.count { stop(); index = 0; position = 0 }
        }
    }

    func play() {
        guard tape != nil else { message = "Load a tape from the shelf first."; return }
        guard !tracks.isEmpty else { message = "Side \(side.rawValue) is blank. Flip the tape or record songs onto it."; return }
        thunk.impactOccurred()
        if mode == .paused, resumeAudio() { mode = .playing; startTicker(); return }
        startTrack(at: index, from: position)
    }

    func pause() {
        guard mode == .playing else { return }
        thunk.impactOccurred()
        demo?.pause()
        if !simulated { system.pause() }
        mode = .paused
    }

    func togglePlay() { mode == .playing ? pause() : play() }

    func stop() {
        thunk.impactOccurred()
        stopAudio()
        mode = .stopped
    }

    /// Fast-forward key: cue to the next song on this side.
    func fastForward() {
        guard !tracks.isEmpty else { return }
        cue(forward: true) {
            if self.index + 1 < self.tracks.count { self.jump(to: self.index + 1) } else { self.endOfSide() }
        }
    }

    /// Rewind key: back to the start of this song, or to the previous one
    /// when already at the start.
    func rewind() {
        guard !tracks.isEmpty else { return }
        cue(forward: false) {
            if self.position > 3 || self.index == 0 { self.jump(to: self.index, from: 0) }
            else { self.jump(to: self.index - 1) }
        }
    }

    func flip() {
        guard tape != nil else { return }
        let wasPlaying = mode == .playing
        stopAudio()
        side = side.flipped
        index = 0
        position = 0
        mode = .stopped
        thunk.impactOccurred(intensity: 1)
        if wasPlaying && !tracks.isEmpty { startTrack(at: 0, from: 0) }
    }

    func select(_ i: Int) {
        guard tracks.indices.contains(i) else { return }
        thunk.impactOccurred()
        startTrack(at: i, from: 0)
    }

    // MARK: Engine

    private func jump(to i: Int, from start: TimeInterval = 0) {
        let resume = mode == .playing || { if case .cueing = mode { return true } else { return false } }()
        if resume && cueResumes { startTrack(at: i, from: start) }
        else { stopAudio(); index = i; position = start; mode = .stopped }
    }
    private var cueResumes = false

    private func cue(forward: Bool, then action: @escaping () -> Void) {
        cueResumes = (mode == .playing)
        thunk.impactOccurred()
        demo?.pause()
        if !simulated && cueResumes { system.pause() }
        mode = .cueing(forward: forward)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if self.cueResumes { self.mode = .playing }
            action()
            if case .cueing = self.mode { self.mode = .stopped }
        }
    }

    private func startTrack(at i: Int, from start: TimeInterval) {
        stopAudio()
        guard tracks.indices.contains(i) else { return }
        index = i
        position = start
        let track = tracks[i]
        simulated = false
        switch track.source {
        case .demo(let name):
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { message = "Couldn't open the demo recording."; return }
            try? AVAudioSession.sharedInstance().setActive(true)
            p.currentTime = start
            p.play()
            demo = p
        case .library(let pid):
            guard let item = MusicLibrary.mediaItem(pid) else {
                message = "\u{201C}\(track.title)\u{201D} is no longer in your music library, so it was skipped."
                advance(); return
            }
            system.setQueue(with: MPMediaItemCollection(items: [item]))
            system.prepareToPlay()
            system.currentPlaybackTime = start
            system.play()
        case .sample:
            simulated = true
        }
        sawPlaying = false
        mode = .playing
        startTicker()
    }

    @discardableResult
    private func resumeAudio() -> Bool {
        guard let track = current else { return false }
        switch track.source {
        case .demo: guard let d = demo else { return false }; d.play()
        case .library: system.play()
        case .sample: break
        }
        return true
    }

    private func stopAudio() {
        ticker = nil
        demo?.stop()
        demo = nil
        if system.playbackState != .stopped { system.stop() }
    }

    private func startTicker() {
        ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard mode == .playing, let track = current else { return }
        switch track.source {
        case .demo:
            guard let d = demo else { return }
            position = d.currentTime
            // AVAudioPlayer stops by itself at the end of the recording.
            if !d.isPlaying || d.currentTime >= d.duration - 0.05 { advance() }
        case .library:
            let t = system.currentPlaybackTime
            if system.playbackState == .playing { sawPlaying = true; if t.isFinite { position = t } }
            else if sawPlaying && (system.playbackState == .stopped || position >= track.duration - 1.5) { advance() }
        case .sample:
            position += 0.2
            if position >= track.duration { advance() }
        }
    }

    private func advance() {
        if index + 1 < tracks.count { startTrack(at: index + 1, from: 0) } else { endOfSide() }
    }

    private func endOfSide() {
        stopAudio()
        if side == .a && autoReverse && !(tape?.sideB.isEmpty ?? true) {
            side = .b; index = 0; position = 0
            thunk.impactOccurred(intensity: 1)
            if cueResumes || mode == .playing { startTrack(at: 0, from: 0) } else { mode = .stopped }
        } else {
            index = max(0, tracks.count - 1)
            position = current?.duration ?? 0
            mode = .stopped
        }
    }

    // MARK: Screenshots

    /// Screenshot data: shows a tape mid-song without audio.
    func stage(_ tape: Tape, side: TapeSide, index: Int, position: TimeInterval, playing: Bool) {
        stopAudio()
        self.tape = tape
        self.side = side
        self.index = index
        self.position = position
        simulated = true
        mode = playing ? .playing : .paused
        if playing { startTicker() }
    }
}
