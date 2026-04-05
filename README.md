# RetroPlayer

A retro portable music player simulator for iOS, built entirely in SwiftUI. Features a functional click wheel interface, hierarchical menu system, music playback simulation, and classic retro games.

## Features

### Click Wheel Interface
- **Rotate** the wheel ring clockwise/counter-clockwise to scroll through menus
- **MENU** (top) — navigate back
- **Play/Pause** (bottom) — toggle music playback
- **Previous/Next** (left/right) — skip tracks
- **Center button** — select/confirm
- Haptic feedback on every interaction

### Music Player
- Browse songs and albums through a classic menu hierarchy
- Now Playing screen with album artwork, progress bar, and volume indicator
- Track-to-track advancement and shuffle mode
- Simulated playback with timer-based progress

### Retro Games
- **Vortex** — a brick breaker game controlled entirely via the click wheel
  - Rotate the wheel to move the paddle
  - Press Select to launch the ball
  - 5 rows of color-coded bricks, 3 lives, score tracking

### Device Simulation
- Silver metallic body with gradient finish
- Black-bezeled LCD screen with status bar
- Battery indicator and playback status icons
- Backlight toggle in Settings

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Getting Started

1. Clone the repository
2. Open `MusicPlayer.xcodeproj` in Xcode
3. Build and run on a simulator or device

## Architecture

- **SwiftUI** — entire UI layer
- **Combine** — reactive state management and timers
- **MVVM** — `RetroPlayerViewModel` manages all navigation, playback, and menu state
- Single `ContentView.swift` contains the device shell, click wheel, and all screen views
- `VortexGameView.swift` contains the brick breaker game engine and rendering

## License

MIT
