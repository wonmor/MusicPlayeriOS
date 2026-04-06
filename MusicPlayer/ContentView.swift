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
    case settings
    case about
}

// MARK: - ViewModel

class RetroPlayerViewModel: ObservableObject {
    @Published var currentScreen: MenuScreen = .main
    @Published var menuStack: [MenuScreen] = []
    @Published var selectedIndex: Int = 0
    @Published var currentSong: Song
    @Published var isPlaying: Bool = false
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
    private var cancellables = Set<AnyCancellable>()
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let player = ApplicationMusicPlayer.shared

    init() {
        currentSong = Song(title: "No Music", artist: "Connect Apple Music", artwork: "", duration: 0)

        $isPlaying
            .sink { [weak self] playing in
                if playing { self?.startTimer() } else { self?.stopTimer() }
            }
            .store(in: &cancellables)
    }

    // MARK: MusicKit

    func requestMusicAuthorization() {
        Task {
            let status = await MusicAuthorization.request()
            await MainActor.run {
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
                // Load songs
                var songRequest = MusicLibraryRequest<MusicKit.Song>()
                songRequest.limit = 100
                songRequest.sort(by: \.title, ascending: true)
                let songResponse = try await songRequest.response()

                let libSongs: [Song] = songResponse.items.map { mkSong in
                    let artURL = mkSong.artwork?.url(width: 200, height: 200)
                    return Song(
                        title: mkSong.title,
                        artist: mkSong.artistName,
                        artwork: "",
                        duration: mkSong.duration ?? 0,
                        musicKitSong: mkSong,
                        artworkURL: artURL
                    )
                }

                // Load albums
                var albumRequest = MusicLibraryRequest<MusicKit.Album>()
                albumRequest.limit = 50
                albumRequest.sort(by: \.title, ascending: true)
                let albumResponse = try await albumRequest.response()

                let libAlbums: [Album] = albumResponse.items.map { mkAlbum in
                    let artURL = mkAlbum.artwork?.url(width: 200, height: 200)
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
        case .main: return "RetroPlayer"
        case .music: return "Music"
        case .songs: return "Songs"
        case .albums: return "Albums"
        case .nowPlaying: return "Now Playing"
        case .extras: return "Extras"
        case .games: return "Games"
        case .vortex: return "Vortex"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var maxIndex: Int {
        switch currentScreen {
        case .songs: return max(0, songs.count - 1)
        case .nowPlaying, .vortex, .about: return 0
        default: return max(0, menuItems.count - 1)
        }
    }

    // MARK: Navigation

    func select() {
        haptic.impactOccurred()
        if currentScreen == .vortex {
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
            if selectedIndex == 0 { navigateTo(.games) }
        case .games:
            if selectedIndex == 0 { navigateTo(.vortex) }
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
        if currentScreen == .vortex {
            gameScrollHandler?(-1)
            haptic.impactOccurred()
            return
        }
        guard currentScreen != .nowPlaying && currentScreen != .about else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
            haptic.impactOccurred()
        }
    }

    func scrollDown() {
        if currentScreen == .vortex {
            gameScrollHandler?(1)
            haptic.impactOccurred()
            return
        }
        guard currentScreen != .nowPlaying && currentScreen != .about else { return }
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
            vm.requestMusicAuthorization()
        }
    }
}

// MARK: - iPhone: Retro Device

struct RetroDeviceView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 10)

                VStack(spacing: 20) {
                    ScreenView(vm: vm)
                        .frame(height: 260)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    Spacer(minLength: 8)

                    ClickWheelView(
                        onScroll: { direction in
                            if direction > 0 { vm.scrollDown() } else { vm.scrollUp() }
                        },
                        onCenter: { vm.select() },
                        onMenu: { vm.goBack() },
                        onPlay: { vm.togglePlayPause() },
                        onNext: { vm.nextTrack() },
                        onPrevious: { vm.previousTrack() }
                    )
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.85, blue: 0.87),
                                    Color(red: 0.75, green: 0.75, blue: 0.77),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                )

                Spacer(minLength: 10)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - iPad: Classic Music Manager

struct ClassicManagerView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @State private var selectedSidebarItem: SidebarItem = .songs
    @State private var searchText: String = ""
    @State private var selectedSongIndex: Int? = nil

    enum SidebarItem: String, CaseIterable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        case genres = "Genres"
        case recentlyAdded = "Recently Added"
    }

    var filteredSongs: [Song] {
        if searchText.isEmpty {
            return vm.songs
        }
        return vm.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            ClassicToolbarView(vm: vm, searchText: $searchText)

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Sidebar
                ClassicSidebarView(
                    selected: $selectedSidebarItem,
                    songCount: vm.songs.count
                )

                Divider()

                // Content area
                VStack(spacing: 0) {
                    // Column headers
                    ClassicColumnHeaderView()

                    Divider()

                    // Song list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredSongs.enumerated()), id: \.offset) { index, song in
                                ClassicSongRowView(
                                    song: song,
                                    index: index,
                                    isSelected: selectedSongIndex == index,
                                    isPlaying: vm.currentSong.title == song.title && vm.currentSong.artist == song.artist && vm.isPlaying,
                                    isEven: index % 2 == 0
                                )
                                .onTapGesture {
                                    selectedSongIndex = index
                                }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        vm.playSong(at: index)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            // Bottom playback bar
            ClassicPlaybackBarView(vm: vm)
        }
        .background(Color(red: 0.93, green: 0.93, blue: 0.93))
    }
}

// MARK: - Classic Toolbar

struct ClassicToolbarView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            // Playback controls
            HStack(spacing: 4) {
                Button(action: { vm.previousTrack() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(ClassicButtonStyle())

                Button(action: { vm.togglePlayPause() }) {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(ClassicButtonStyle())

                Button(action: { vm.nextTrack() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(ClassicButtonStyle())
            }

            // Volume
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Slider(value: $vm.volume, in: 0...1)
                    .frame(width: 100)
                    .tint(.gray)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Now Playing display
            if vm.isPlaying || vm.progress > 0 {
                VStack(spacing: 2) {
                    Text(vm.currentSong.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(vm.currentSong.artist)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    // Progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: vm.currentSong.duration > 0
                                    ? geo.size.width * min(1, vm.progress / vm.currentSong.duration)
                                    : 0)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(width: 220)
            }

            Spacer()

            // Search bar
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                TextField("Search", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .frame(width: 180)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.88, blue: 0.90),
                    Color(red: 0.78, green: 0.78, blue: 0.80),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Classic Button Style

struct ClassicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .frame(width: 32, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [Color(white: 0.7), Color(white: 0.7)]
                                : [Color(white: 0.95), Color(white: 0.82)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Classic Sidebar

struct ClassicSidebarView: View {
    @Binding var selected: ClassicManagerView.SidebarItem
    let songCount: Int

    private let sidebarItems: [(icon: String, item: ClassicManagerView.SidebarItem)] = [
        ("music.note", .songs),
        ("square.stack", .albums),
        ("person.2.fill", .artists),
        ("guitars.fill", .genres),
        ("clock.fill", .recentlyAdded),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Library header
            Text("LIBRARY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(sidebarItems, id: \.item) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 12))
                        .foregroundColor(selected == entry.item ? .white : .blue)
                        .frame(width: 18)
                    Text(entry.item.rawValue)
                        .font(.system(size: 13))
                        .foregroundColor(selected == entry.item ? .white : .primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selected == entry.item
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.blue)
                        : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                )
                .padding(.horizontal, 6)
                .onTapGesture { selected = entry.item }
            }

            Spacer()

            // Song count
            Text("\(songCount) songs")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(width: 180)
        .background(Color(red: 0.90, green: 0.91, blue: 0.92))
    }
}

// MARK: - Column Header

struct ClassicColumnHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 30)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 16)
            Text("Artist")
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 8)
            Divider().frame(height: 16)
            Text("Time")
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Song Row

struct ClassicSongRowView: View {
    let song: Song
    let index: Int
    let isSelected: Bool
    let isPlaying: Bool
    let isEven: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Play indicator
            ZStack {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? .white : .blue)
                }
            }
            .frame(width: 30)

            // Artwork + Title
            HStack(spacing: 8) {
                if let url = song.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 28, height: 28)
                    .cornerRadius(3)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
                Text(song.title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Artist
            Text(song.artist)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 8)
                .lineLimit(1)

            // Duration
            Text(formatDuration(song.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected
                ? Color.blue
                : (isEven ? Color(white: 0.96) : Color.white)
        )
    }

    private func formatDuration(_ secs: Double) -> String {
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Playback Bar (Bottom)

struct ClassicPlaybackBarView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Artwork
            if let url = vm.currentSong.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 40, height: 40)
                .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }

            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.currentSong.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(vm.currentSong.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)

            // Time
            Text(vm.formatTime(vm.progress))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: vm.currentSong.duration > 0
                            ? geo.size.width * min(1, vm.progress / vm.currentSong.duration)
                            : 0)
                }
            }
            .frame(height: 4)

            Text("-\(vm.formatTime(max(0, vm.currentSong.duration - vm.progress)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            // Shuffle / Repeat
            Button(action: {}) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Image(systemName: "repeat")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.88, blue: 0.90),
                    Color(red: 0.82, green: 0.82, blue: 0.84),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Screen View

struct ScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(title: vm.screenTitle, isPlaying: vm.isPlaying)

            ZStack {
                Color.white

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

// MARK: - Status Bar

struct StatusBarView: View {
    let title: String
    let isPlaying: Bool

    var body: some View {
        HStack {
            if isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
            }
            Spacer()
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(Color.black, lineWidth: 0.5)
                    .frame(width: 18, height: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.green.opacity(0.8))
                            .padding(1.5)
                    )
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 1.5, height: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.75, green: 0.78, blue: 0.82),
                    Color(red: 0.65, green: 0.68, blue: 0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundColor(.black)
    }
}

// MARK: - Menu List

struct MenuListView: View {
    let items: [(String, String)]
    let selectedIndex: Int
    let showChevron: Bool

    private let highlightGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
        startPoint: .top, endPoint: .bottom
    )
    private let clearGradient = LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let selected = index == selectedIndex
                HStack(spacing: 8) {
                    Image(systemName: item.1)
                        .font(.system(size: 12))
                        .frame(width: 20)
                        .foregroundColor(selected ? .white : .gray)
                    Text(item.0)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(selected ? .white : .black)
                    Spacer()
                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(selected ? .white : .gray)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selected ? highlightGradient : clearGradient)
            }
            Spacer()
        }
    }
}

// MARK: - Song List Screen

struct SongListScreenView: View {
    let songs: [Song]
    let selectedIndex: Int

    private let highlightGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
        startPoint: .top, endPoint: .bottom
    )
    private let clearGradient = LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        let selected = index == selectedIndex
                        HStack(spacing: 6) {
                            // Artwork thumbnail
                            if let url = song.artworkURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 22, height: 22)
                                .cornerRadius(2)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 10))
                                    .foregroundColor(selected ? .white : .gray)
                                    .frame(width: 22, height: 22)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selected ? .white : .black)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(selected ? .white.opacity(0.8) : .gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatDuration(song.duration))
                                .font(.system(size: 10))
                                .foregroundColor(selected ? .white.opacity(0.8) : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? highlightGradient : clearGradient)
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

    private let highlightGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
        startPoint: .top, endPoint: .bottom
    )
    private let clearGradient = LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                        let selected = index == selectedIndex
                        HStack(spacing: 6) {
                            if let url = album.artworkURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 22, height: 22)
                                .cornerRadius(2)
                            } else {
                                Image(systemName: "square.stack")
                                    .font(.system(size: 10))
                                    .foregroundColor(selected ? .white : .gray)
                                    .frame(width: 22, height: 22)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(album.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selected ? .white : .black)
                                    .lineLimit(1)
                                Text(album.year)
                                    .font(.system(size: 10))
                                    .foregroundColor(selected ? .white.opacity(0.8) : .gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundColor(selected ? .white : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? highlightGradient : clearGradient)
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

// MARK: - Now Playing Screen

struct NowPlayingScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(currentTrackIndex + 1) of \(vm.songs.count)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Album art — real artwork or fallback
            if let url = vm.currentSong.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(1, contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
                .frame(maxHeight: 110)
                .cornerRadius(4)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(.horizontal, 40)
            } else if !vm.currentSong.artwork.isEmpty {
                Image(vm.currentSong.artwork)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: 110)
                    .cornerRadius(4)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .padding(.horizontal, 40)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 110, height: 110)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 28))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }

            VStack(spacing: 1) {
                Text(vm.currentSong.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                Text(vm.currentSong.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.top, 2)

            // Progress bar
            VStack(spacing: 2) {
                GeometryReader { geo in
                    let fraction = vm.currentSong.duration > 0
                        ? min(1, vm.progress / vm.currentSong.duration)
                        : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.2, green: 0.45, blue: 0.9))
                            .frame(width: geo.size.width * fraction, height: 4)
                        Circle()
                            .fill(Color(red: 0.2, green: 0.45, blue: 0.9))
                            .frame(width: 8, height: 8)
                            .offset(x: max(0, (geo.size.width - 8) * fraction))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(vm.formatTime(vm.progress))
                    Spacer()
                    Text("-\(vm.formatTime(max(0, vm.currentSong.duration - vm.progress)))")
                }
                .font(.system(size: 9))
                .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            // Volume bar
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.gray)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: geo.size.width * vm.volume, height: 3)
                    }
                }
                .frame(height: 3)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private var currentTrackIndex: Int {
        vm.songs.firstIndex(where: { $0.title == vm.currentSong.title && $0.artist == vm.currentSong.artist }) ?? 0
    }
}

// MARK: - About Screen

struct AboutScreenView: View {
    let musicAuthorized: Bool

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray)
            Text("RetroPlayer")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
            Text("Version 1.0")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Text("A retro portable\nmusic player simulator")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            HStack(spacing: 4) {
                Circle()
                    .fill(musicAuthorized ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(musicAuthorized ? "Apple Music Connected" : "Apple Music Not Connected")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .padding(.top, 4)
            Spacer()
        }
    }
}

// MARK: - Click Wheel

struct ClickWheelView: View {
    let onScroll: (Int) -> Void
    let onCenter: () -> Void
    let onMenu: () -> Void
    let onPlay: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    @State private var lastAngle: Double?
    @State private var accumulatedAngle: Double = 0
    private let scrollThreshold: Double = 18

    private let wheelSize: CGFloat = 210
    private var centerSize: CGFloat { wheelSize * 0.36 }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.82), Color(white: 0.76)],
                        center: .center,
                        startRadius: 40,
                        endRadius: 105
                    )
                )
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                .frame(width: wheelSize * 0.72)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.95), Color(white: 0.88)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 40
                    )
                )
                .frame(width: centerSize, height: centerSize)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .onTapGesture { onCenter() }

            Text("MENU")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(white: 0.4))
                .offset(y: -wheelSize * 0.33)

            Image(systemName: "playpause.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .offset(y: wheelSize * 0.33)

            Image(systemName: "backward.end.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .offset(x: -wheelSize * 0.33)

            Image(systemName: "forward.end.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .offset(x: wheelSize * 0.33)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let center = CGPoint(x: wheelSize / 2, y: wheelSize / 2)
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance > centerSize / 2 else { return }

                    let angle = atan2(dy, dx) * 180 / .pi
                    if let last = lastAngle {
                        var delta = angle - last
                        if delta > 180 { delta -= 360 }
                        if delta < -180 { delta += 360 }
                        accumulatedAngle += delta
                        if accumulatedAngle >= scrollThreshold {
                            onScroll(1)
                            accumulatedAngle = 0
                        } else if accumulatedAngle <= -scrollThreshold {
                            onScroll(-1)
                            accumulatedAngle = 0
                        }
                    }
                    lastAngle = angle
                }
                .onEnded { _ in
                    lastAngle = nil
                    accumulatedAngle = 0
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in
                    let travel = abs(value.translation.width) + abs(value.translation.height)
                    guard travel < 8 else { return }

                    let center = CGPoint(x: wheelSize / 2, y: wheelSize / 2)
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    let distance = sqrt(dx * dx + dy * dy)

                    if distance < centerSize / 2 {
                        onCenter()
                    } else if distance < wheelSize / 2 {
                        if abs(dy) > abs(dx) {
                            if dy < 0 { onMenu() } else { onPlay() }
                        } else {
                            if dx < 0 { onPrevious() } else { onNext() }
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
