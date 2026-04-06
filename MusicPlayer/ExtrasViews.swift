import SwiftUI
import Combine

// MARK: - Clock Screen

struct ClockScreenView: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            // Analog clock face
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)

                // Hour markers
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 10 : 6)
                        .offset(y: -54)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                // Hour hand
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 3, height: 30)
                    .offset(y: -15)
                    .rotationEffect(hourAngle)

                // Minute hand
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 2, height: 42)
                    .offset(y: -21)
                    .rotationEffect(minuteAngle)

                // Second hand
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1, height: 46)
                    .offset(y: -23)
                    .rotationEffect(secondAngle)

                // Center dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }

            // Digital time
            Text(timeString)
                .font(.system(size: 24, weight: .light, design: .monospaced))
                .foregroundColor(.black)

            // Date
            Text(dateString)
                .font(.system(size: 11))
                .foregroundColor(.gray)

            Spacer()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private var calendar: Calendar { Calendar.current }

    private var hourAngle: Angle {
        let hour = Double(calendar.component(.hour, from: currentTime) % 12)
        let minute = Double(calendar.component(.minute, from: currentTime))
        return .degrees((hour + minute / 60) * 30)
    }

    private var minuteAngle: Angle {
        let minute = Double(calendar.component(.minute, from: currentTime))
        let second = Double(calendar.component(.second, from: currentTime))
        return .degrees((minute + second / 60) * 6)
    }

    private var secondAngle: Angle {
        .degrees(Double(calendar.component(.second, from: currentTime)) * 6)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f.string(from: currentTime)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: currentTime)
    }
}

// MARK: - Stopwatch Screen

struct StopwatchScreenView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @State private var elapsed: TimeInterval = 0
    @State private var isRunning = false
    @State private var laps: [TimeInterval] = []
    @State private var timer: AnyCancellable?
    @State private var startDate: Date?

    var body: some View {
        VStack(spacing: 6) {
            // Time display
            Text(formatStopwatch(elapsed))
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .foregroundColor(.black)
                .padding(.top, 12)

            // Status
            Text(isRunning ? "Running" : (elapsed > 0 ? "Stopped" : "Press Select"))
                .font(.system(size: 10))
                .foregroundColor(.gray)

            // Controls hint
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 0.2, green: 0.45, blue: 0.9))
                    Text(isRunning ? "Lap" : (elapsed > 0 ? "Reset" : "Start"))
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 4)

            // Laps
            if !laps.isEmpty {
                Divider().padding(.horizontal, 10)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(laps.enumerated().reversed()), id: \.offset) { index, lap in
                            HStack {
                                Text("Lap \(index + 1)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.black)
                                Spacer()
                                Text(formatStopwatch(lap))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            vm.gameSelectHandler = { [self] in
                if isRunning {
                    // Lap
                    laps.append(elapsed)
                } else if elapsed > 0 {
                    // Reset
                    elapsed = 0
                    laps = []
                } else {
                    // Start
                    isRunning = true
                    startDate = Date()
                    startTimer()
                }
            }
            vm.gameScrollHandler = nil
        }
        .onDisappear {
            timer?.cancel()
            vm.gameSelectHandler = nil
        }
        .onChange(of: isRunning) { running in
            if running {
                startDate = Date().addingTimeInterval(-elapsed)
                startTimer()
            } else {
                timer?.cancel()
            }
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if let start = startDate {
                    elapsed = Date().timeIntervalSince(start)
                }
            }
    }

    private func formatStopwatch(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, hundredths)
    }
}

// MARK: - Solitaire (Card Matching Game)

struct Card: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

class SolitaireGameState: ObservableObject {
    @Published var cards: [Card] = []
    @Published var score: Int = 0
    @Published var moves: Int = 0
    @Published var selectedIndex: Int = 0
    @Published var gameWon: Bool = false

    private var firstFlippedIndex: Int?

    init() { resetGame() }

    func resetGame() {
        let symbols = ["♠", "♥", "♦", "♣", "★", "●", "▲", "■"]
        var deck = symbols.flatMap { [$0, $0] }
        deck.shuffle()
        cards = deck.map { Card(symbol: $0) }
        score = 0
        moves = 0
        selectedIndex = 0
        firstFlippedIndex = nil
        gameWon = false
    }

    func selectCard() {
        let index = selectedIndex
        guard index < cards.count, !cards[index].isMatched, !cards[index].isFaceUp else { return }

        cards[index].isFaceUp = true

        if let first = firstFlippedIndex {
            moves += 1
            if cards[first].symbol == cards[index].symbol {
                // Match
                cards[first].isMatched = true
                cards[index].isMatched = true
                score += 10
                firstFlippedIndex = nil

                if cards.allSatisfy(\.isMatched) {
                    gameWon = true
                }
            } else {
                // No match — flip back after delay
                let f = first
                let i = index
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.cards[f].isFaceUp = false
                    self?.cards[i].isFaceUp = false
                }
                firstFlippedIndex = nil
            }
        } else {
            firstFlippedIndex = index
        }
    }

    func moveLeft() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    func moveRight() {
        if selectedIndex < cards.count - 1 { selectedIndex += 1 }
    }
}

struct SolitaireGameView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @StateObject private var game = SolitaireGameState()

    let columns = 4

    var body: some View {
        GeometryReader { geo in
            let cardW = (geo.size.width - 30) / CGFloat(columns)
            let cardH = cardW * 1.2

            ZStack {
                Color(red: 0.0, green: 0.25, blue: 0.1)

                VStack(spacing: 2) {
                    // Header
                    HStack {
                        Text("Score: \(game.score)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        Text("Moves: \(game.moves)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    // Card grid
                    VStack(spacing: 3) {
                        ForEach(0..<(game.cards.count / columns), id: \.self) { row in
                            HStack(spacing: 3) {
                                ForEach(0..<columns, id: \.self) { col in
                                    let index = row * columns + col
                                    if index < game.cards.count {
                                        CardView(
                                            card: game.cards[index],
                                            isSelected: game.selectedIndex == index,
                                            width: cardW - 3,
                                            height: cardH - 3
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)

                    Spacer()
                }

                if game.gameWon {
                    VStack(spacing: 6) {
                        Text("YOU WIN!")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow)
                        Text("Moves: \(game.moves)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Press Select to Play Again")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                }
            }
        }
        .onAppear {
            game.resetGame()
            vm.gameScrollHandler = { direction in
                if direction > 0 { game.moveRight() } else { game.moveLeft() }
            }
            vm.gameSelectHandler = {
                if game.gameWon {
                    game.resetGame()
                } else {
                    game.selectCard()
                }
            }
        }
        .onDisappear {
            vm.gameScrollHandler = nil
            vm.gameSelectHandler = nil
        }
    }
}

struct CardView: View {
    let card: Card
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if card.isMatched {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: width, height: height)
            } else if card.isFaceUp {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: width, height: height)
                Text(card.symbol)
                    .font(.system(size: min(width, height) * 0.45))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.3, blue: 0.7), Color(red: 0.15, green: 0.2, blue: 0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: width, height: height)
                // Card back pattern
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: width - 6, height: height - 6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
                .frame(width: width, height: height)
        )
    }
}

// MARK: - Quiz Game (Music Trivia)

struct QuizQuestion {
    let question: String
    let options: [String]
    let correctIndex: Int
}

class QuizGameState: ObservableObject {
    @Published var currentQuestion: Int = 0
    @Published var score: Int = 0
    @Published var selectedOption: Int = 0
    @Published var answered: Bool = false
    @Published var wasCorrect: Bool = false
    @Published var gameOver: Bool = false

    let questions: [QuizQuestion] = [
        QuizQuestion(question: "What year was the Walkman released?", options: ["1975", "1979", "1982", "1985"], correctIndex: 1),
        QuizQuestion(question: "How many keys on a standard piano?", options: ["76", "82", "88", "92"], correctIndex: 2),
        QuizQuestion(question: "Which instrument has 6 strings?", options: ["Violin", "Guitar", "Bass", "Banjo"], correctIndex: 1),
        QuizQuestion(question: "What does BPM stand for?", options: ["Bars Per Measure", "Beats Per Minute", "Bass Power Mode", "Band Performance Mix"], correctIndex: 1),
        QuizQuestion(question: "Which music format came first?", options: ["CD", "Cassette", "Vinyl", "MP3"], correctIndex: 2),
        QuizQuestion(question: "How many notes in an octave?", options: ["6", "7", "8", "12"], correctIndex: 3),
        QuizQuestion(question: "What is the fastest tempo called?", options: ["Allegro", "Vivace", "Presto", "Prestissimo"], correctIndex: 3),
        QuizQuestion(question: "Which clef is used for high notes?", options: ["Bass", "Treble", "Alto", "Tenor"], correctIndex: 1),
    ]

    func answer() {
        guard !answered && !gameOver else {
            if answered {
                nextQuestion()
            } else if gameOver {
                restart()
            }
            return
        }
        answered = true
        wasCorrect = selectedOption == questions[currentQuestion].correctIndex
        if wasCorrect { score += 1 }
    }

    func nextQuestion() {
        if currentQuestion + 1 < questions.count {
            currentQuestion += 1
            selectedOption = 0
            answered = false
        } else {
            gameOver = true
        }
    }

    func restart() {
        currentQuestion = 0
        score = 0
        selectedOption = 0
        answered = false
        wasCorrect = false
        gameOver = false
    }

    func moveUp() {
        guard !answered else { return }
        if selectedOption > 0 { selectedOption -= 1 }
    }

    func moveDown() {
        guard !answered else { return }
        if selectedOption < questions[currentQuestion].options.count - 1 { selectedOption += 1 }
    }
}

struct QuizGameView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @StateObject private var game = QuizGameState()

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.08, blue: 0.2)

            if game.gameOver {
                VStack(spacing: 8) {
                    Text("QUIZ COMPLETE")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("\(game.score) / \(game.questions.count)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                    Text(game.score == game.questions.count ? "Perfect!" :
                         game.score >= game.questions.count / 2 ? "Good job!" : "Try again!")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("Press Select to Restart")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
            } else {
                let q = game.questions[game.currentQuestion]

                VStack(spacing: 6) {
                    // Progress
                    HStack {
                        Text("Q\(game.currentQuestion + 1)/\(game.questions.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("Score: \(game.score)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    // Question
                    Text(q.question)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                    // Options
                    VStack(spacing: 4) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { index, option in
                            let isSelected = game.selectedOption == index
                            let bgColor: Color = {
                                if game.answered {
                                    if index == q.correctIndex { return .green.opacity(0.7) }
                                    if isSelected && !game.wasCorrect { return .red.opacity(0.7) }
                                }
                                return isSelected ? Color(red: 0.3, green: 0.2, blue: 0.6) : Color.white.opacity(0.1)
                            }()

                            HStack {
                                Text("\(["A", "B", "C", "D"][index]).")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .white : .gray)
                                    .frame(width: 18)
                                Text(option)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                Spacer()
                                if game.answered && index == q.correctIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(bgColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.yellow.opacity(0.8) : Color.clear, lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal, 8)

                    if game.answered {
                        Text("Press Select to continue")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            game.restart()
            vm.gameSelectHandler = { game.answer() }
            vm.gameScrollHandler = { direction in
                if direction > 0 { game.moveDown() } else { game.moveUp() }
            }
        }
        .onDisappear {
            vm.gameSelectHandler = nil
            vm.gameScrollHandler = nil
        }
    }
}
