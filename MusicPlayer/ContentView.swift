import SwiftUI
import Combine

// MARK: - Models

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let artwork: String
    let duration: Double
}

struct Album: Identifiable {
    let id = UUID()
    let title: String
    let artwork: String
    let year: String
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

    // Game integration - set by VortexGameView
    var gameScrollHandler: ((Int) -> Void)?
    var gameSelectHandler: (() -> Void)?

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    let songs: [Song] = [
        Song(title: "Sick Feeling", artist: "Boy Pablo", artwork: "profile", duration: 220),
        Song(title: "Everytime", artist: "Boy Pablo", artwork: "profile", duration: 185),
        Song(title: "Feeling Lonely", artist: "Boy Pablo", artwork: "profile", duration: 200),
        Song(title: "Honey", artist: "Boy Pablo", artwork: "profile", duration: 205),
        Song(title: "Dance, Baby!", artist: "Boy Pablo", artwork: "profile", duration: 199),
        Song(title: "Losing You", artist: "Boy Pablo", artwork: "profile", duration: 193),
    ]

    let albums: [Album] = [
        Album(title: "Soy Pablo", artwork: "profile", year: "2018"),
        Album(title: "Wachito Rico", artwork: "profile", year: "2020"),
    ]

    init() {
        currentSong = Song(title: "Everytime", artist: "Boy Pablo", artwork: "profile", duration: 185)
        $isPlaying
            .sink { [weak self] playing in
                if playing { self?.startTimer() } else { self?.stopTimer() }
            }
            .store(in: &cancellables)
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
        case .songs: return songs.count - 1
        case .nowPlaying, .vortex, .about: return 0
        default: return menuItems.count - 1
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
            isPlaying.toggle()
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
    }

    func shuffleAndPlay() {
        if let song = songs.randomElement() {
            currentSong = song
            progress = 0
            isPlaying = true
            navigateTo(.nowPlaying)
        }
    }

    func togglePlayPause() {
        haptic.impactOccurred()
        isPlaying.toggle()
    }

    func nextTrack() {
        haptic.impactOccurred()
        if let idx = songs.firstIndex(where: { $0.title == currentSong.title }) {
            playSong(at: (idx + 1) % songs.count)
        }
    }

    func previousTrack() {
        haptic.impactOccurred()
        if progress > 3 {
            progress = 0
        } else if let idx = songs.firstIndex(where: { $0.title == currentSong.title }) {
            playSong(at: (idx - 1 + songs.count) % songs.count)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.progress < self.currentSong.duration {
                    self.progress += 1
                } else {
                    self.nextTrack()
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 10)

                // Device body
                VStack(spacing: 20) {
                    // Screen
                    ScreenView(vm: vm)
                        .frame(height: 260)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    Spacer(minLength: 8)

                    // Click wheel
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

// MARK: - Screen View

struct ScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            StatusBarView(title: vm.screenTitle, isPlaying: vm.isPlaying)

            // Screen content
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
                    AboutScreenView()
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
            // Battery
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: item.1)
                        .font(.system(size: 12))
                        .frame(width: 20)
                        .foregroundColor(index == selectedIndex ? .white : .gray)
                    Text(item.0)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(index == selectedIndex ? .white : .black)
                    Spacer()
                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(index == selectedIndex ? .white : .gray)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    index == selectedIndex
                        ? LinearGradient(
                            colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                        : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
                )
            }
            Spacer()
        }
    }
}

// MARK: - Song List Screen

struct SongListScreenView: View {
    let songs: [Song]
    let selectedIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(index == selectedIndex ? .white : .gray)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(index == selectedIndex ? .white : .black)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 10))
                            .foregroundColor(index == selectedIndex ? .white.opacity(0.8) : .gray)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatDuration(song.duration))
                        .font(.system(size: 10))
                        .foregroundColor(index == selectedIndex ? .white.opacity(0.8) : .gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    index == selectedIndex
                        ? LinearGradient(
                            colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                        : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
                )
            }
            Spacer()
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
        VStack(spacing: 0) {
            ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                HStack(spacing: 8) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 10))
                        .foregroundColor(index == selectedIndex ? .white : .gray)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(album.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(index == selectedIndex ? .white : .black)
                        Text(album.year)
                            .font(.system(size: 10))
                            .foregroundColor(index == selectedIndex ? .white.opacity(0.8) : .gray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(index == selectedIndex ? .white : .gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    index == selectedIndex
                        ? LinearGradient(
                            colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.15, green: 0.35, blue: 0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                        : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
                )
            }
            Spacer()
        }
    }
}

// MARK: - Now Playing Screen

struct NowPlayingScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Track info
            HStack {
                Text("\(currentTrackIndex + 1) of \(vm.songs.count)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Album art
            Image(vm.currentSong.artwork)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 110)
                .cornerRadius(4)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(.horizontal, 40)

            // Song info
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
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.2, green: 0.45, blue: 0.9))
                            .frame(
                                width: vm.currentSong.duration > 0
                                    ? geo.size.width * (vm.progress / vm.currentSong.duration)
                                    : 0,
                                height: 4
                            )
                        // Scrubber dot
                        Circle()
                            .fill(Color(red: 0.2, green: 0.45, blue: 0.9))
                            .frame(width: 8, height: 8)
                            .offset(
                                x: vm.currentSong.duration > 0
                                    ? (geo.size.width - 8) * (vm.progress / vm.currentSong.duration)
                                    : 0
                            )
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
        vm.songs.firstIndex(where: { $0.title == vm.currentSong.title }) ?? 0
    }
}

// MARK: - About Screen

struct AboutScreenView: View {
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
            // Outer wheel
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

            // Subtle ring line
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                .frame(width: wheelSize * 0.72)

            // Center button
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

            // Labels
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

                    // Only process on the ring area
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
                    guard travel < 8 else { return } // Only process taps

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
