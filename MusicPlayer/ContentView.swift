import SwiftUI

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

// MARK: - ViewModel
class PlayerViewModel: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var currentSong: Song = Song(
        title: "Feeling Lonely",
        artist: "Boy Pablo",
        artwork: "soy_pablo",
        duration: 200
    )
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0.0

    // Sample data
    let albums: [Album] = [
        Album(title: "Soy Pablo", artwork: "soy_pablo", year: "2018"),
        Album(title: "Wachito Rico", artwork: "wachito_rico", year: "2020")
    ]
    let songs: [Song] = [
        Song(title: "Sick Feeling", artist: "Soy Pablo", artwork: "soy_pablo", duration: 220),
        Song(title: "EveryTime", artist: "Soy Pablo", artwork: "soy_pablo", duration: 185),
        Song(title: "Feeling Lonely", artist: "Soy Pablo", artwork: "soy_pablo", duration: 200),
        Song(title: "Honey", artist: "Soy Pablo", artwork: "soy_pablo", duration: 205)
    ]
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var vm = PlayerViewModel()
    @Namespace private var animation
    @State private var selectedTab: Tab = .albums

    enum Tab: String, CaseIterable {
        case popular = "Popular"
        case albums = "Albums"
        case singles = "Singles"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ArtistHeaderView()
                Picker("Tab", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \ .self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                Group {
                    switch selectedTab {
                    case .albums:
                        AlbumGridView(albums: vm.albums)
                    case .popular:
                        SongListView(songs: vm.songs, vm: vm, animation: animation)
                    case .singles:
                        SongListView(songs: vm.songs, vm: vm, animation: animation)
                    }
                }
                .padding(.horizontal)
                Spacer(minLength: 80)
            }
            .background(Color(.systemBackground).ignoresSafeArea())

            // Mini / Full Player
            if vm.isExpanded {
                FullPlayerView(vm: vm, animation: animation)
                    .transition(.move(edge: .bottom))
            } else {
                MiniPlayerView(vm: vm, animation: animation)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.isExpanded)
    }
}

// MARK: - Artist Header
struct ArtistHeaderView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemYellow).ignoresSafeArea().frame(height: 300)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 48)
                
                Text("Boy Pablo")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal)
                Text("16,105,208 monthly listeners")
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)
                Button(action: {}) {
                    Text("Follow")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(20)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Album Grid
struct AlbumGridView: View {
    let albums: [Album]
    let columns = Array(repeating: GridItem(.flexible()), count: 2)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(albums) { album in
                VStack(alignment: .leading) {
                    Image(album.artwork)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .cornerRadius(8)
                    Text(album.title).font(.headline)
                    Text(album.year).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.top)
    }
}

// MARK: - Song List
struct SongListView: View {
    let songs: [Song]
    @ObservedObject var vm: PlayerViewModel
    var animation: Namespace.ID
    var body: some View {
        VStack(spacing: 12) {
            ForEach(songs) { song in
                HStack {
                    Image(song.artwork)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                        .matchedGeometryEffect(id: "artwork", in: animation)
                    VStack(alignment: .leading) {
                        Text(song.title).lineLimit(1)
                        Text(song.artist).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if vm.currentSong.id == song.id && vm.isPlaying {
                        Button(action: { vm.isPlaying.toggle() }) {
                            Image(systemName: "pause.fill")
                        }
                    } else {
                        Button(action: {
                            vm.currentSong = song
                            vm.isPlaying = true
                        }) {
                            Image(systemName: "play.fill")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.top)
    }
}

// MARK: - Mini & Full Player
// (Same as your existing mini/full player code)

struct MiniPlayerView: View {
    @ObservedObject var vm: PlayerViewModel
    var animation: Namespace.ID

    var body: some View {
        HStack(spacing: 16) {
            Image(vm.currentSong.artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(6)
                .matchedGeometryEffect(id: "artwork", in: animation)

            VStack(alignment: .leading) {
                Text(vm.currentSong.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(vm.currentSong.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            Button(action: { vm.isPlaying.toggle() }) {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(BlurView(style: .systemMaterial))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onTapGesture {
            vm.isExpanded = true
        }
    }
}

struct FullPlayerView: View {
    @ObservedObject var vm: PlayerViewModel
    var animation: Namespace.ID
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Spacer()

            Image(vm.currentSong.artwork)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .matchedGeometryEffect(id: "artwork", in: animation)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 8) {
                Text(vm.currentSong.title)
                    .font(.title)
                    .bold()
                Text(vm.currentSong.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Slider(value: $vm.progress, in: 0...vm.currentSong.duration)
                .padding(.horizontal, 32)

            HStack {
                Text(formatTime(vm.progress))
                Spacer()
                Text(formatTime(vm.currentSong.duration))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            HStack(spacing: 40) {
                Button(action: {}) { Image(systemName: "backward.fill") }
                Button(action: { vm.isPlaying.toggle() }) {
                    Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }
                Button(action: {}) { Image(systemName: "forward.fill") }
            }
            .font(.title2)
            .padding(.bottom, 32)

            Spacer()
        }
        .background(BlurView(style: .systemMaterial).ignoresSafeArea())
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 {
                        state = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 150 {
                        vm.isExpanded = false
                    }
                }
        )
    }

    private func formatTime(_ secs: Double) -> String {
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Blur Helper
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
