# iRetroMusic

A mixtape maker and hi-fi cassette deck for iPhone, in SwiftUI.

- **Record tapes**: choose C46, C60 or C90, label the tape, pick a shell colour and record songs from the device's music library onto side A and side B. Each side only holds half the running time; songs that don't fit aren't recorded.
- **Play them on the deck**: REW, PLAY, F.FWD, STOP and FLIP piano keys, a three-digit tape counter, reels whose tape packs grow and shrink with the side's progress (constant tape speed, so the emptier reel turns faster), auto-reverse, a vacuum-fluorescent display and VU meters.
- **Shelf**: every tape is kept as a cassette spine; touch and hold to edit, duplicate or delete.
- **Demo Tape**: three short original instrumentals synthesised by `scripts/demotape.py`, bundled so the deck plays before the user records anything.

## Code

- `Models.swift`: tracks, tape formats, shells, tapes, the shelf (JSON in Documents) and the demo tape.
- `Deck.swift`: music-library access (MediaPlayer) and the deck engine (system music player for library songs, AVAudioPlayer for the demo tape).
- `DeckView.swift`: cassette, counter, display, meters, keys, running order.
- `ShelfView.swift`: shelf, tape editor and song picker.
- `ScreenshotData.swift`: Debug-only store-screenshot fixtures (`-ui-shot deck|shelf|about|demo|sideb`).

Requires iOS 18.5+. Contact: john@orchestrsim.com

## License

MIT
