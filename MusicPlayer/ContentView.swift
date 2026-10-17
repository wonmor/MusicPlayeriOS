import SwiftUI
import Combine
import MusicKit

// MARK: - Models

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let artwork: String
    let duration: Double
    var musicKitSong: MusicKit.Song?
    var artworkURL: URL?
}

struct Album: Identifiable {
    let id = UUID()
    let title: String
    let artwork: String
    let year: String
    var artworkURL: URL?
}

// MARK: - Navigation

enum MenuScreen: Equatable {
    case main
    case music
    case songs
    case albums
    case nowPlaying
    case extras
    case games
    case vortex
    case solitaire
    case quiz
    case clock
    case stopwatch
    case settings
    case about
}

// MARK: - ViewModel

class RetroPlayerViewModel: ObservableObject {
    @Published var currentScreen: MenuScreen = .main
    @Published var menuStack: [MenuScreen] = []
    @Published var selectedIndex: Int = 0
    @Published var currentSong: Song
    @Published var isPlaying: Bool = false {
        didSet {
            if isPlaying { startTimer() } else { stopTimer() }
        }
    }
    @Published var progress: Double = 0.0
    @Published var volume: Double = 0.5
    @Published var backlightOn: Bool = true
    @Published var musicAuthorized: Bool = false
    @Published var libraryLoaded: Bool = false

    @Published var songs: [Song] = []
    @Published var albums: [Album] = []

    // Game integration
    var gameScrollHandler: ((Int) -> Void)?
    var gameSelectHandler: (() -> Void)?

    private var timer: AnyCancellable?
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let player = ApplicationMusicPlayer.shared

    static let sampleSongs: [Song] = [
        Song(title: "Midnight Drive", artist: "Neon Waves", artwork: "profile", duration: 214),
        Song(title: "Sunlit Morning", artist: "Pastel Skies", artwork: "profile", duration: 197),
        Song(title: "Ocean Breeze", artist: "Coral Drift", artwork: "profile", duration: 223),
        Song(title: "City Lights", artist: "Neon Waves", artwork: "profile", duration: 185),
        Song(title: "Golden Hour", artist: "Pastel Skies", artwork: "profile", duration: 201),
        Song(title: "Starfall", artist: "Coral Drift", artwork: "profile", duration: 190),
    ]

    static let sampleAlbums: [Album] = [
        Album(title: "Electric Dreams", artwork: "profile", year: "2024"),
        Album(title: "Coastal", artwork: "profile", year: "2025"),
    ]

    init() {
        let samples = Self.sampleSongs
        currentSong = samples[0]
        songs = samples
        albums = Self.sampleAlbums
        applyLaunchScreenOverride()
    }

    /// Screenshot/UI-test aid: launching with `-ui-screen <name>` opens that screen directly
    /// (nowPlaying, songs, albums, about, settings, extras, clock, stopwatch, vortex, quiz).
    static var isScreenshotLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-screen")
    }

    private func applyLaunchScreenOverride() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ui-screen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "nowPlaying": menuStack = [.main]; currentScreen = .nowPlaying; progress = 72
        case "songs": menuStack = [.main, .music]; currentScreen = .songs
        case "albums": menuStack = [.main, .music]; currentScreen = .albums
        case "about": menuStack = [.main, .settings]; currentScreen = .about
        case "settings": menuStack = [.main]; currentScreen = .settings
        case "extras": menuStack = [.main]; currentScreen = .extras
        case "clock": menuStack = [.main, .extras]; currentScreen = .clock
        case "stopwatch": menuStack = [.main, .extras]; currentScreen = .stopwatch
        case "vortex": menuStack = [.main, .extras, .games]; currentScreen = .vortex
        case "quiz": menuStack = [.main, .extras, .games]; currentScreen = .quiz
        default: break
        }
    }

    // MARK: MusicKit

    func requestMusicAuthorization() {
        Task { @MainActor in
            do {
                let status = await MusicAuthorization.request()
                self.musicAuthorized = (status == .authorized)
                if self.musicAuthorized {
                    self.loadLibrary()
                }
            }
        }
    }

    func loadLibrary() {
        Task {
            do {
                var songRequest = MusicLibraryRequest<MusicKit.Song>()
                songRequest.limit = 100
                songRequest.sort(by: \.title, ascending: true)
                let songResponse = try await songRequest.response()

                let libSongs: [Song] = songResponse.items.map { mkSong in
                    let artURL = mkSong.artwork?.url(width: 300, height: 300)
                    return Song(
                        title: mkSong.title,
                        artist: mkSong.artistName,
                        artwork: "",
                        duration: mkSong.duration ?? 0,
                        musicKitSong: mkSong,
                        artworkURL: artURL
                    )
                }

                var albumRequest = MusicLibraryRequest<MusicKit.Album>()
                albumRequest.limit = 50
                albumRequest.sort(by: \.title, ascending: true)
                let albumResponse = try await albumRequest.response()

                let libAlbums: [Album] = albumResponse.items.map { mkAlbum in
                    let artURL = mkAlbum.artwork?.url(width: 300, height: 300)
                    let year = mkAlbum.releaseDate.map { String(Calendar.current.component(.year, from: $0)) } ?? ""
                    return Album(
                        title: mkAlbum.title,
                        artwork: "",
                        year: year,
                        artworkURL: artURL
                    )
                }

                await MainActor.run {
                    if !libSongs.isEmpty {
                        self.songs = libSongs
                        self.currentSong = libSongs[0]
                    }
                    if !libAlbums.isEmpty {
                        self.albums = libAlbums
                    }
                    self.libraryLoaded = true
                }
            } catch {
                print("Failed to load library: \(error)")
                await MainActor.run {
                    self.libraryLoaded = true
                }
            }
        }
    }

    // MARK: Menu Items

    var menuItems: [(String, String)] {
        switch currentScreen {
        case .main:
            return [
                ("Music", "music.note.list"),
                ("Extras", "star.fill"),
                ("Settings", "gearshape.fill"),
                ("Shuffle Songs", "shuffle"),
                ("Now Playing", "play.circle.fill"),
            ]
        case .music:
            return [
                ("All Songs", "music.note"),
                ("Albums", "square.stack"),
                ("Artists", "person.2.fill"),
            ]
        case .extras:
            return [
                ("Games", "gamecontroller.fill"),
                ("Clock", "clock.fill"),
                ("Stopwatch", "stopwatch.fill"),
            ]
        case .games:
            return [
                ("Vortex", "hurricane"),
                ("Solitaire", "suit.spade.fill"),
                ("Quiz", "questionmark.circle.fill"),
            ]
        case .settings:
            return [
                ("About", "info.circle.fill"),
                ("Backlight", backlightOn ? "lightbulb.fill" : "lightbulb"),
                ("Repeat", "repeat"),
            ]
        default:
            return []
        }
    }

    var screenTitle: String {
        switch currentScreen {
        case .main: return "iRetroMusic"
        case .music: return "Music"
        case .songs: return "Songs"
        case .albums: return "Albums"
        case .nowPlaying: return "Now Playing"
        case .extras: return "Extras"
        case .games: return "Games"
        case .vortex: return "Vortex"
        case .solitaire: return "Solitaire"
        case .quiz: return "Quiz"
        case .clock: return "Clock"
        case .stopwatch: return "Stopwatch"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var maxIndex: Int {
        switch currentScreen {
        case .songs: return max(0, songs.count - 1)
        case .nowPlaying, .vortex, .solitaire, .quiz, .clock, .stopwatch, .about: return 0
        default: return max(0, menuItems.count - 1)
        }
    }

    // MARK: Navigation

    func select() {
        haptic.impactOccurred()
        if currentScreen == .vortex || currentScreen == .solitaire
            || currentScreen == .stopwatch || currentScreen == .quiz {
            gameSelectHandler?()
            return
        }
        switch currentScreen {
        case .main:
            switch selectedIndex {
            case 0: navigateTo(.music)
            case 1: navigateTo(.extras)
            case 2: navigateTo(.settings)
            case 3: shuffleAndPlay()
            case 4: if isPlaying || progress > 0 { navigateTo(.nowPlaying) }
            default: break
            }
        case .music:
            switch selectedIndex {
            case 0: navigateTo(.songs)
            case 1: navigateTo(.albums)
            default: break
            }
        case .songs:
            playSong(at: selectedIndex)
            navigateTo(.nowPlaying)
        case .extras:
            switch selectedIndex {
            case 0: navigateTo(.games)
            case 1: navigateTo(.clock)
            case 2: navigateTo(.stopwatch)
            default: break
            }
        case .games:
            switch selectedIndex {
            case 0: navigateTo(.vortex)
            case 1: navigateTo(.solitaire)
            case 2: navigateTo(.quiz)
            default: break
            }
        case .settings:
            switch selectedIndex {
            case 0: navigateTo(.about)
            case 1: backlightOn.toggle()
            default: break
            }
        case .nowPlaying:
            togglePlayPause()
        default: break
        }
    }

    func navigateTo(_ screen: MenuScreen) {
        menuStack.append(currentScreen)
        currentScreen = screen
        selectedIndex = 0
    }

    func goBack() {
        haptic.impactOccurred()
        if let previous = menuStack.popLast() {
            currentScreen = previous
            selectedIndex = 0
        }
    }

    func scrollUp() {
        if currentScreen == .vortex || currentScreen == .solitaire {
            gameScrollHandler?(-1)
            haptic.impactOccurred()
            return
        }
        guard currentScreen != .nowPlaying && currentScreen != .about
                && currentScreen != .clock && currentScreen != .stopwatch
                && currentScreen != .quiz else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
            haptic.impactOccurred()
        }
    }

    func scrollDown() {
        if currentScreen == .vortex || currentScreen == .solitaire {
            gameScrollHandler?(1)
            haptic.impactOccurred()
            return
        }
        guard currentScreen != .nowPlaying && currentScreen != .about
                && currentScreen != .clock && currentScreen != .stopwatch
                && currentScreen != .quiz else { return }
        if selectedIndex < maxIndex {
            selectedIndex += 1
            haptic.impactOccurred()
        }
    }

    // MARK: Playback

    func playSong(at index: Int) {
        guard index < songs.count else { return }
        currentSong = songs[index]
        progress = 0
        // Force restart timer even if already playing
        stopTimer()
        isPlaying = true

        if let mkSong = currentSong.musicKitSong {
            Task {
                player.queue = [mkSong]
                do {
                    try await player.play()
                } catch {
                    print("Playback error: \(error)")
                }
            }
        }
    }

    func shuffleAndPlay() {
        guard !songs.isEmpty else { return }
        let index = Int.random(in: 0..<songs.count)
        playSong(at: index)
        navigateTo(.nowPlaying)
    }

    func togglePlayPause() {
        haptic.impactOccurred()
        isPlaying.toggle()

        if currentSong.musicKitSong != nil {
            if isPlaying {
                Task { try? await player.play() }
            } else {
                player.pause()
            }
        }
    }

    func nextTrack() {
        haptic.impactOccurred()
        if let idx = songs.firstIndex(where: { $0.title == currentSong.title && $0.artist == currentSong.artist }) {
            playSong(at: (idx + 1) % songs.count)
        }
    }

    func previousTrack() {
        haptic.impactOccurred()
        if progress > 3 {
            progress = 0
            if currentSong.musicKitSong != nil {
                player.restartCurrentEntry()
            }
        } else if let idx = songs.firstIndex(where: { $0.title == currentSong.title && $0.artist == currentSong.artist }) {
            playSong(at: (idx - 1 + songs.count) % songs.count)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.currentSong.musicKitSong != nil {
                    // Track real playback progress
                    self.progress = self.player.playbackTime
                    // Check if track ended
                    if self.currentSong.duration > 0 && self.progress >= self.currentSong.duration - 0.5 {
                        self.nextTrack()
                    }
                } else {
                    // Simulated playback
                    if self.progress < self.currentSong.duration {
                        self.progress += 0.5
                    } else {
                        self.nextTrack()
                    }
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    func formatTime(_ secs: Double) -> String {
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Content View (Device Shell)

struct ContentView: View {
    @StateObject private var vm = RetroPlayerViewModel()
    @Environment(\.horizontalSizeClass) var sizeClass

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ClassicManagerView(vm: vm)
            } else {
                RetroDeviceView(vm: vm)
            }
        }
        .onAppear {
            if !RetroPlayerViewModel.isScreenshotLaunch { vm.requestMusicAuthorization() }
        }
    }
}

// MARK: - iPhone: Cassette Deck Player

struct RetroDeviceView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.07, blue: 0.05), Color(red: 0.05, green: 0.04, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 6)

                VStack(spacing: 12) {
                    DeckBrandStrip(isPlaying: vm.isPlaying)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    CassetteWindowView(isPlaying: vm.isPlaying)
                        .frame(height: 64)
                        .padding(.horizontal, 18)

                    ScreenView(vm: vm)
                        .frame(height: 200)
                        .padding(.horizontal, 18)

                    NavButtonRow(vm: vm)
                        .padding(.horizontal, 18)

                    TransportButtonRow(vm: vm)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.97, green: 0.65, blue: 0.25),
                                    Color(red: 0.85, green: 0.48, blue: 0.15),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color(red: 0.35, green: 0.16, blue: 0.04), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
                )

                Spacer(minLength: 6)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Cassette Deck Components

struct DeckBrandStrip: View {
    let isPlaying: Bool

    var body: some View {
        HStack {
            Text("iRetroMusic")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Color(red: 0.30, green: 0.12, blue: 0.04))
                .tracking(1)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(isPlaying ? Color(red: 0.95, green: 0.20, blue: 0.10) : Color.black.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .shadow(color: isPlaying ? Color(red: 1, green: 0.3, blue: 0.1) : .clear, radius: 4)
                Text("PWR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.30, green: 0.12, blue: 0.04))
            }
        }
    }
}

struct CassetteWindowView: View {
    let isPlaying: Bool
    @State private var rotation: Double = 0
    @State private var animTimer: Timer?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.85), Color.black.opacity(0.72)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.30, green: 0.12, blue: 0.04), lineWidth: 1.5)
                )

            Rectangle()
                .fill(Color(red: 0.45, green: 0.28, blue: 0.10))
                .frame(height: 4)
                .offset(y: 8)

            HStack(spacing: 56) {
                CassetteReel(angle: rotation)
                CassetteReel(angle: rotation)
            }
        }
        .onAppear { updateAnimation() }
        .onChange(of: isPlaying) { _ in updateAnimation() }
        .onDisappear {
            animTimer?.invalidate()
            animTimer = nil
        }
    }

    private func updateAnimation() {
        animTimer?.invalidate()
        if isPlaying {
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                rotation = (rotation + 6).truncatingRemainder(dividingBy: 360)
            }
        } else {
            animTimer = nil
        }
    }
}

struct CassetteReel: View {
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.50, green: 0.30, blue: 0.15), lineWidth: 1)
                .frame(width: 34, height: 34)
            Circle()
                .fill(Color(red: 0.18, green: 0.10, blue: 0.04))
                .frame(width: 26, height: 26)
            ForEach(0..<6, id: \.self) { i in
                Rectangle()
                    .fill(Color(red: 0.55, green: 0.35, blue: 0.18))
                    .frame(width: 1.5, height: 18)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Circle()
                .fill(Color(red: 0.40, green: 0.22, blue: 0.10))
                .frame(width: 6, height: 6)
        }
        .rotationEffect(.degrees(angle))
    }
}

struct DeckButton: View {
    let label: String?
    let icon: String?
    let action: () -> Void
    var width: CGFloat = 56
    var height: CGFloat = 40
    var prominent: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: prominent
                                ? [Color(red: 0.32, green: 0.20, blue: 0.10), Color(red: 0.18, green: 0.10, blue: 0.05)]
                                : [Color(red: 0.22, green: 0.14, blue: 0.08), Color(red: 0.12, green: 0.07, blue: 0.04)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.black.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 2)

                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.95, green: 0.92, blue: 0.85))
                        .tracking(0.5)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.92, blue: 0.85))
                }
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(DeckPressStyle())
    }
}

struct DeckPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct NavButtonRow: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        HStack(spacing: 8) {
            DeckButton(label: nil, icon: "chevron.up",
                          action: { vm.scrollUp() }, width: 60, height: 40)
            DeckButton(label: "OK", icon: nil,
                          action: { vm.select() }, width: 76, height: 40, prominent: true)
            DeckButton(label: nil, icon: "chevron.down",
                          action: { vm.scrollDown() }, width: 60, height: 40)
            DeckButton(label: "BACK", icon: nil,
                          action: { vm.goBack() }, width: 60, height: 40)
        }
    }
}

struct TransportButtonRow: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        HStack(spacing: 10) {
            DeckButton(label: nil, icon: "backward.fill",
                          action: { vm.previousTrack() }, width: 72, height: 46)
            DeckButton(label: nil, icon: vm.isPlaying ? "pause.fill" : "play.fill",
                          action: { vm.togglePlayPause() }, width: 96, height: 46, prominent: true)
            DeckButton(label: nil, icon: "forward.fill",
                          action: { vm.nextTrack() }, width: 72, height: 46)
        }
    }
}

// MARK: - iPad: Card Grid Library

struct ClassicManagerView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @State private var selectedTab: GridTab = .songs
    @State private var searchText: String = ""

    enum GridTab: String, CaseIterable {
        case songs = "Tracks"
        case albums = "Albums"
        case nowPlaying = "Player"
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return vm.songs }
        return vm.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredAlbums: [Album] {
        guard !searchText.isEmpty else { return vm.albums }
        return vm.albums.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.07, blue: 0.05), Color(red: 0.05, green: 0.03, blue: 0.02)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                IPadHeaderBar(selectedTab: $selectedTab, searchText: $searchText)

                ScrollView {
                    Group {
                        switch selectedTab {
                        case .songs:
                            IPadSongGrid(songs: filteredSongs, vm: vm)
                        case .albums:
                            IPadAlbumGrid(albums: filteredAlbums)
                        case .nowPlaying:
                            IPadNowPlayingPanel(vm: vm)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }

                IPadMiniPlayer(vm: vm)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private let iPadAccent = Color(red: 0.95, green: 0.55, blue: 0.15)
private let iPadAccentDeep = Color(red: 0.78, green: 0.38, blue: 0.08)
private let iPadCardBG = Color(red: 0.16, green: 0.12, blue: 0.09)
private let iPadCardBGRaised = Color(red: 0.21, green: 0.16, blue: 0.12)

struct IPadHeaderBar: View {
    @Binding var selectedTab: ClassicManagerView.GridTab
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "radio.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(iPadAccent)
                Text("iRetroMusic")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.92, blue: 0.85))
                    .tracking(0.5)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(ClassicManagerView.GridTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                    }) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedTab == tab ? .white : Color(white: 0.65))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        selectedTab == tab
                                            ? AnyShapeStyle(LinearGradient(
                                                colors: [iPadAccent, iPadAccentDeep],
                                                startPoint: .top, endPoint: .bottom))
                                            : AnyShapeStyle(Color.clear)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(iPadCardBG)
            )

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                TextField("", text: $searchText, prompt: Text("Search").foregroundColor(Color(white: 0.45)))
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.92))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(iPadCardBG)
            )
            .frame(width: 220)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.07, blue: 0.05), Color(red: 0.07, green: 0.05, blue: 0.04)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct IPadSongGrid: View {
    let songs: [Song]
    @ObservedObject var vm: RetroPlayerViewModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 18)]
    }

    var body: some View {
        if songs.isEmpty {
            EmptyStateView(message: "No tracks found")
        } else {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongCard(
                        song: song,
                        isPlaying: vm.currentSong.title == song.title
                            && vm.currentSong.artist == song.artist
                            && vm.isPlaying
                    )
                    .onTapGesture {
                        if let i = vm.songs.firstIndex(where: { $0.id == song.id }) {
                            vm.playSong(at: i)
                        }
                    }
                }
            }
        }
    }
}

struct SongCard: View {
    let song: Song
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = song.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(iPadCardBGRaised)
                        }
                    } else {
                        Rectangle()
                            .fill(iPadCardBGRaised)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 36))
                                    .foregroundColor(Color(white: 0.45))
                            )
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if isPlaying {
                    HStack(spacing: 3) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("PLAYING")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [iPadAccent, iPadAccentDeep],
                            startPoint: .top, endPoint: .bottom))
                    )
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.95))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(iPadCardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPlaying ? iPadAccent.opacity(0.6) : Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

struct IPadAlbumGrid: View {
    let albums: [Album]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 22)]
    }

    var body: some View {
        if albums.isEmpty {
            EmptyStateView(message: "No albums found")
        } else {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(albums) { album in
                    AlbumCard(album: album)
                }
            }
        }
    }
}

struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let url = album.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(iPadCardBGRaised)
                    }
                } else {
                    Rectangle()
                        .fill(iPadCardBGRaised)
                        .overlay(
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(white: 0.45))
                        )
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.95))
                    .lineLimit(1)
                if !album.year.isEmpty {
                    Text(album.year)
                        .font(.system(size: 11))
                        .foregroundColor(iPadAccent)
                }
            }
        }
    }
}

struct IPadNowPlayingPanel: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            ZStack {
                Group {
                    if let url = vm.currentSong.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(iPadCardBGRaised)
                        }
                    } else {
                        Rectangle()
                            .fill(iPadCardBGRaised)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 80))
                                    .foregroundColor(Color(white: 0.4))
                            )
                    }
                }
                .frame(width: 320, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
            }

            VStack(spacing: 6) {
                Text(vm.currentSong.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.95))
                Text(vm.currentSong.artist)
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.65))
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let fraction = vm.currentSong.duration > 0
                        ? min(1, vm.progress / vm.currentSong.duration)
                        : 0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [iPadAccent, iPadAccentDeep],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * fraction, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(vm.formatTime(vm.progress))
                    Spacer()
                    Text("-\(vm.formatTime(max(0, vm.currentSong.duration - vm.progress)))")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
            }
            .frame(maxWidth: 380)

            HStack(spacing: 28) {
                IPadCircleButton(icon: "backward.fill", size: 44) { vm.previousTrack() }
                IPadCircleButton(icon: vm.isPlaying ? "pause.fill" : "play.fill",
                                 size: 64, prominent: true) { vm.togglePlayPause() }
                IPadCircleButton(icon: "forward.fill", size: 44) { vm.nextTrack() }
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IPadCircleButton: View {
    let icon: String
    var size: CGFloat = 44
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        prominent
                            ? AnyShapeStyle(LinearGradient(
                                colors: [iPadAccent, iPadAccentDeep],
                                startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(iPadCardBG)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

struct IPadMiniPlayer: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let url = vm.currentSong.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(iPadCardBGRaised)
                    }
                } else {
                    Rectangle()
                        .fill(iPadCardBGRaised)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 16))
                                .foregroundColor(Color(white: 0.5))
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.currentSong.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.95))
                    .lineLimit(1)
                Text(vm.currentSong.artist)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: 240, alignment: .leading)

            GeometryReader { geo in
                let fraction = vm.currentSong.duration > 0
                    ? min(1, vm.progress / vm.currentSong.duration)
                    : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [iPadAccent, iPadAccentDeep],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Button(action: { vm.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.85))
                }
                .buttonStyle(.plain)

                Button(action: { vm.togglePlayPause() }) {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(iPadAccent)
                }
                .buttonStyle(.plain)

                Button(action: { vm.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.07, blue: 0.05), Color(red: 0.07, green: 0.05, blue: 0.04)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(Color(white: 0.35))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

// MARK: - Screen View

struct ScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(title: vm.screenTitle, isPlaying: vm.isPlaying)

            ZStack {
                LCD.panel

                switch vm.currentScreen {
                case .main, .music, .extras, .games, .settings:
                    MenuListView(
                        items: vm.menuItems,
                        selectedIndex: vm.selectedIndex,
                        showChevron: true
                    )
                case .songs:
                    SongListScreenView(
                        songs: vm.songs,
                        selectedIndex: vm.selectedIndex
                    )
                case .albums:
                    AlbumListScreenView(
                        albums: vm.albums,
                        selectedIndex: vm.selectedIndex
                    )
                case .nowPlaying:
                    NowPlayingScreenView(vm: vm)
                case .vortex:
                    VortexGameView(vm: vm)
                case .solitaire:
                    SolitaireGameView(vm: vm)
                case .quiz:
                    QuizGameView(vm: vm)
                case .clock:
                    ClockScreenView()
                case .stopwatch:
                    StopwatchScreenView(vm: vm)
                case .about:
                    AboutScreenView(musicAuthorized: vm.musicAuthorized)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
                .padding(-4)
        )
        .opacity(vm.backlightOn ? 1.0 : 0.6)
    }
}

// MARK: - LCD palette (cassette-deck amber on dark brown)

enum LCD {
    static let ink = Color(red: 0.16, green: 0.11, blue: 0.05)        // text on the cream panel
    static let inkDim = Color(red: 0.45, green: 0.36, blue: 0.24)     // secondary text
    static let panel = Color(red: 0.95, green: 0.93, blue: 0.80)      // cream LCD background
    static let amber = Color(red: 0.98, green: 0.78, blue: 0.32)
    static let amberDeep = Color(red: 0.85, green: 0.42, blue: 0.10)
    static let header = Color(red: 0.20, green: 0.12, blue: 0.05)
    static let cursor = LinearGradient(
        colors: [Color(red: 0.95, green: 0.55, blue: 0.15), Color(red: 0.78, green: 0.38, blue: 0.08)],
        startPoint: .top, endPoint: .bottom
    )
    static let none = LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Status Bar (tape-deck header: left-aligned title, transport state on the right)

struct StatusBarView: View {
    let title: String
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(LCD.mono(10, .bold))
                .tracking(1.2)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Circle()
                    .fill(isPlaying ? Color(red: 0.95, green: 0.25, blue: 0.10) : LCD.amber.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text(isPlaying ? "PLAY" : "STOP")
                    .font(LCD.mono(9, .heavy))
                Text("TAPE A")
                    .font(LCD.mono(8, .semibold))
                    .foregroundColor(LCD.amber.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LCD.header)
        .foregroundColor(LCD.amber)
    }
}

// MARK: - Menu List

struct MenuListView: View {
    let items: [(String, String)]
    let selectedIndex: Int
    let showChevron: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let selected = index == selectedIndex
                LCDRow(selected: selected) {
                    Image(systemName: item.1)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18)
                        .foregroundColor(selected ? LCD.ink : LCD.inkDim)
                    Text(item.0.uppercased())
                        .font(LCD.mono(13, .semibold))
                        .tracking(0.8)
                        .foregroundColor(LCD.ink)
                    Spacer()
                    if showChevron && selected {
                        Text("OK")
                            .font(LCD.mono(8, .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(LCD.ink, lineWidth: 1))
                            .foregroundColor(LCD.ink)
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }
}

/// One line of the cassette-deck LCD: a "▶" cursor marks the selected row, rows are separated by a
/// dotted rule, and the selected row sits on an amber bar.
struct LCDRow<Content: View>: View {
    let selected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(selected ? "\u{25B6}" : " ")
                    .font(LCD.mono(9, .heavy))
                    .foregroundColor(LCD.ink)
                    .frame(width: 10)
                content()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(selected ? LCD.cursor : LCD.none)
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                .foregroundColor(LCD.ink.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, 8)
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Song List Screen

struct SongListScreenView: View {
    let songs: [Song]
    let selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        let selected = index == selectedIndex
                        LCDRow(selected: selected) {
                            Text(String(format: "%02d", index + 1))
                                .font(LCD.mono(9, .bold))
                                .foregroundColor(LCD.inkDim)
                            if let url = song.artworkURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(LCD.ink.opacity(0.15))
                                }
                                .frame(width: 20, height: 20)
                                .cornerRadius(2)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title)
                                    .font(LCD.mono(12, .semibold))
                                    .foregroundColor(LCD.ink)
                                    .lineLimit(1)
                                Text(song.artist.uppercased())
                                    .font(LCD.mono(8))
                                    .foregroundColor(selected ? LCD.ink.opacity(0.8) : LCD.inkDim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatDuration(song.duration))
                                .font(LCD.mono(9))
                                .foregroundColor(selected ? LCD.ink.opacity(0.8) : LCD.inkDim)
                        }
                        .id(index)
                    }
                }
            }
            .onChange(of: selectedIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func formatDuration(_ secs: Double) -> String {
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Album List Screen

struct AlbumListScreenView: View {
    let albums: [Album]
    let selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                        let selected = index == selectedIndex
                        LCDRow(selected: selected) {
                            if let url = album.artworkURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(LCD.ink.opacity(0.15))
                                }
                                .frame(width: 20, height: 20)
                                .cornerRadius(2)
                            } else {
                                Image(systemName: "square.stack")
                                    .font(.system(size: 10))
                                    .foregroundColor(LCD.inkDim)
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(album.title)
                                    .font(LCD.mono(12, .semibold))
                                    .foregroundColor(LCD.ink)
                                    .lineLimit(1)
                                Text(album.year)
                                    .font(LCD.mono(8))
                                    .foregroundColor(selected ? LCD.ink.opacity(0.8) : LCD.inkDim)
                            }
                            Spacer()
                        }
                        .id(index)
                    }
                }
            }
            .onChange(of: selectedIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Now Playing Screen (cassette label: artwork left, track info right, block meters below)

struct NowPlayingScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                artwork
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(LCD.ink, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("TRK \(String(format: "%02d", currentTrackIndex + 1))/\(String(format: "%02d", max(vm.songs.count, 1)))")
                        Text("SIDE A")
                    }
                    .font(LCD.mono(8, .heavy))
                    .foregroundColor(LCD.inkDim)

                    Text(vm.currentSong.title)
                        .font(LCD.mono(13, .bold))
                        .foregroundColor(LCD.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(vm.currentSong.artist.uppercased())
                        .font(LCD.mono(9))
                        .foregroundColor(LCD.inkDim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Image(systemName: vm.isPlaying ? "play.fill" : "pause.fill")
                            .font(.system(size: 7, weight: .black))
                        Text(vm.isPlaying ? "PLAYING" : "PAUSED")
                            .font(LCD.mono(8, .heavy))
                    }
                    .foregroundColor(LCD.amberDeep)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 74)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Line()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                .foregroundColor(LCD.ink.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 10)

            // Block-style tape counter
            VStack(spacing: 3) {
                HStack {
                    Text(vm.formatTime(vm.progress))
                    Spacer()
                    Text("COUNTER")
                    Spacer()
                    Text("-\(vm.formatTime(max(0, vm.currentSong.duration - vm.progress)))")
                }
                .font(LCD.mono(9, .bold))
                .foregroundColor(LCD.ink)

                BlockMeter(fraction: vm.currentSong.duration > 0 ? min(1, vm.progress / vm.currentSong.duration) : 0,
                           blocks: 24, height: 9, fill: LCD.amberDeep)
            }
            .padding(.horizontal, 10)

            // Volume as a short block meter
            HStack(spacing: 6) {
                Text("VOL")
                    .font(LCD.mono(8, .heavy))
                    .foregroundColor(LCD.inkDim)
                BlockMeter(fraction: vm.volume, blocks: 12, height: 6, fill: LCD.ink.opacity(0.7))
                    .frame(width: 110)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = vm.currentSong.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(1, contentMode: .fill)
            } placeholder: {
                artworkPlaceholder
            }
        } else if !vm.currentSong.artwork.isEmpty, UIImage(named: vm.currentSong.artwork) != nil {
            Image(vm.currentSong.artwork)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            LCD.ink.opacity(0.08)
            CassetteReel(angle: 0)
                .scaleEffect(1.2)
                .opacity(0.6)
        }
    }

    private var currentTrackIndex: Int {
        vm.songs.firstIndex(where: { $0.title == vm.currentSong.title && $0.artist == vm.currentSong.artist }) ?? 0
    }
}

/// A segmented LED/LCD-style meter made of discrete blocks.
struct BlockMeter: View {
    let fraction: Double
    var blocks: Int = 20
    var height: CGFloat = 8
    var fill: Color = LCD.amberDeep

    var body: some View {
        let lit = Int((fraction * Double(blocks)).rounded(.down))
        HStack(spacing: 2) {
            ForEach(0..<blocks, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? fill : LCD.ink.opacity(0.12))
            }
        }
        .frame(height: height)
    }
}

// MARK: - About Screen

struct AboutScreenView: View {
    let musicAuthorized: Bool

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "radio.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(red: 0.78, green: 0.40, blue: 0.10))
            Text("iRetroMusic")
                .font(LCD.mono(15, .bold))
                .foregroundColor(LCD.ink)
            Text("VERSION 1.0")
                .font(LCD.mono(9))
                .foregroundColor(LCD.inkDim)
            Text("A cassette-era\nportable music player")
                .font(LCD.mono(9))
                .foregroundColor(LCD.inkDim)
                .multilineTextAlignment(.center)
            HStack(spacing: 4) {
                Circle()
                    .fill(musicAuthorized ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(musicAuthorized ? "Apple Music Connected" : "Apple Music Not Connected")
                    .font(LCD.mono(8))
                    .foregroundColor(LCD.inkDim)
            }
            .padding(.top, 4)
            Spacer()
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
