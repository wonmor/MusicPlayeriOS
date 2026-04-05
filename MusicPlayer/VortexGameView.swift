import SwiftUI
import Combine

// MARK: - Brick Model

struct Brick: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    var isAlive: Bool = true
    var color: Color

    var rect: CGRect {
        let cols = 8
        let brickW: CGFloat = 270 / CGFloat(cols)
        let brickH: CGFloat = 12
        let x = CGFloat(col) * brickW
        let y = CGFloat(row) * (brickH + 2) + 24
        return CGRect(x: x, y: y, width: brickW - 2, height: brickH)
    }
}

// MARK: - Game State

enum VortexState {
    case ready
    case playing
    case paused
    case gameOver
    case won
}

class VortexGameEngine: ObservableObject {
    @Published var paddleX: CGFloat = 0.5 // 0-1 normalized
    @Published var ballPos: CGPoint = .zero
    @Published var bricks: [Brick] = []
    @Published var score: Int = 0
    @Published var lives: Int = 3
    @Published var gameState: VortexState = .ready

    var ballVelocity: CGPoint = .zero
    private var timer: AnyCancellable?

    let screenWidth: CGFloat = 270
    let screenHeight: CGFloat = 210
    let paddleWidth: CGFloat = 50
    let paddleHeight: CGFloat = 6
    let ballRadius: CGFloat = 4
    private let ballSpeed: CGFloat = 2.8

    init() {
        resetGame()
    }

    func resetGame() {
        score = 0
        lives = 3
        gameState = .ready
        paddleX = 0.5
        buildBricks()
        resetBall()
    }

    func buildBricks() {
        bricks = []
        let cols = 8
        let rows = 5
        let colors: [Color] = [
            Color(red: 0.9, green: 0.2, blue: 0.2),
            Color(red: 0.9, green: 0.5, blue: 0.1),
            Color(red: 0.9, green: 0.8, blue: 0.1),
            Color(red: 0.2, green: 0.8, blue: 0.3),
            Color(red: 0.2, green: 0.5, blue: 0.9),
        ]
        for row in 0..<rows {
            for col in 0..<cols {
                bricks.append(Brick(row: row, col: col, color: colors[row]))
            }
        }
    }

    func resetBall() {
        let px = paddleX * screenWidth
        ballPos = CGPoint(x: px, y: screenHeight - 20)
        ballVelocity = .zero
    }

    func launch() {
        guard gameState == .ready || gameState == .paused else { return }
        if gameState == .ready {
            let angle = CGFloat.random(in: -0.4...0.4)
            ballVelocity = CGPoint(
                x: ballSpeed * sin(angle),
                y: -ballSpeed * cos(angle)
            )
        }
        gameState = .playing
        startLoop()
    }

    func restart() {
        stopLoop()
        resetGame()
    }

    func movePaddleLeft() {
        paddleX = max(0.1, paddleX - 0.05)
        if gameState == .ready {
            ballPos.x = paddleX * screenWidth
        }
    }

    func movePaddleRight() {
        paddleX = min(0.9, paddleX + 0.05)
        if gameState == .ready {
            ballPos.x = paddleX * screenWidth
        }
    }

    // MARK: Game Loop

    private func startLoop() {
        stopLoop()
        timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stopLoop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard gameState == .playing else { return }

        // Move ball
        ballPos.x += ballVelocity.x
        ballPos.y += ballVelocity.y

        // Wall collisions
        if ballPos.x - ballRadius <= 0 {
            ballPos.x = ballRadius
            ballVelocity.x = abs(ballVelocity.x)
        }
        if ballPos.x + ballRadius >= screenWidth {
            ballPos.x = screenWidth - ballRadius
            ballVelocity.x = -abs(ballVelocity.x)
        }
        if ballPos.y - ballRadius <= 0 {
            ballPos.y = ballRadius
            ballVelocity.y = abs(ballVelocity.y)
        }

        // Bottom - lose life
        if ballPos.y + ballRadius >= screenHeight {
            lives -= 1
            if lives <= 0 {
                gameState = .gameOver
                stopLoop()
            } else {
                resetBall()
                gameState = .ready
                stopLoop()
            }
            return
        }

        // Paddle collision
        let px = paddleX * screenWidth - paddleWidth / 2
        let paddleRect = CGRect(
            x: px,
            y: screenHeight - 14,
            width: paddleWidth,
            height: paddleHeight
        )
        if ballVelocity.y > 0 && ballPos.y + ballRadius >= paddleRect.minY
            && ballPos.y + ballRadius <= paddleRect.maxY + 4
            && ballPos.x >= paddleRect.minX - ballRadius
            && ballPos.x <= paddleRect.maxX + ballRadius
        {
            ballPos.y = paddleRect.minY - ballRadius
            // Angle based on where ball hit paddle
            let hitPos = (ballPos.x - paddleRect.midX) / (paddleWidth / 2)
            let angle = hitPos * 0.7 // max ~40 degree deflection
            let speed = sqrt(ballVelocity.x * ballVelocity.x + ballVelocity.y * ballVelocity.y)
            ballVelocity = CGPoint(
                x: speed * sin(angle),
                y: -speed * cos(angle)
            )
            // Slight speed increase over time
            ballVelocity.x *= 1.01
            ballVelocity.y *= 1.01
        }

        // Brick collisions
        for i in bricks.indices {
            guard bricks[i].isAlive else { continue }
            let brickRect = bricks[i].rect
            if ballPos.x + ballRadius >= brickRect.minX
                && ballPos.x - ballRadius <= brickRect.maxX
                && ballPos.y + ballRadius >= brickRect.minY
                && ballPos.y - ballRadius <= brickRect.maxY
            {
                bricks[i].isAlive = false
                score += 10

                // Determine bounce direction
                let overlapLeft = (ballPos.x + ballRadius) - brickRect.minX
                let overlapRight = brickRect.maxX - (ballPos.x - ballRadius)
                let overlapTop = (ballPos.y + ballRadius) - brickRect.minY
                let overlapBottom = brickRect.maxY - (ballPos.y - ballRadius)
                let minOverlap = min(overlapLeft, overlapRight, overlapTop, overlapBottom)

                if minOverlap == overlapLeft || minOverlap == overlapRight {
                    ballVelocity.x = -ballVelocity.x
                } else {
                    ballVelocity.y = -ballVelocity.y
                }
                break // one brick per frame
            }
        }

        // Check win
        if bricks.allSatisfy({ !$0.isAlive }) {
            gameState = .won
            stopLoop()
        }
    }
}

// MARK: - Vortex Game View

struct VortexGameView: View {
    @ObservedObject var vm: RetroPlayerViewModel
    @StateObject private var game = VortexGameEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12)

                // Bricks
                ForEach(game.bricks.filter(\.isAlive)) { brick in
                    let scale = geo.size.width / game.screenWidth
                    let rect = brick.rect
                    RoundedRectangle(cornerRadius: 2)
                        .fill(brick.color)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .position(
                            x: (rect.midX) * scale,
                            y: (rect.midY) * scale
                        )
                }

                // Paddle
                let pScale = geo.size.width / game.screenWidth
                let yScale = geo.size.height / game.screenHeight
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(
                        width: game.paddleWidth * pScale,
                        height: game.paddleHeight * yScale
                    )
                    .position(
                        x: game.paddleX * geo.size.width,
                        y: (game.screenHeight - 11) * yScale
                    )

                // Ball
                Circle()
                    .fill(Color.white)
                    .frame(
                        width: game.ballRadius * 2 * pScale,
                        height: game.ballRadius * 2 * pScale
                    )
                    .position(
                        x: game.ballPos.x * pScale,
                        y: game.ballPos.y * yScale
                    )

                // Score and lives
                VStack {
                    HStack {
                        Text("Score: \(game.score)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<game.lives, id: \.self) { _ in
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    Spacer()
                }

                // Overlays
                if game.gameState == .ready {
                    VStack(spacing: 4) {
                        Text("VORTEX")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Press Select to Launch")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                        if game.score > 0 {
                            Text("Lives: \(game.lives)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                    }
                }

                if game.gameState == .gameOver {
                    VStack(spacing: 6) {
                        Text("GAME OVER")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.red)
                        Text("Score: \(game.score)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Press Select to Restart")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }

                if game.gameState == .won {
                    VStack(spacing: 6) {
                        Text("YOU WIN!")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.green)
                        Text("Score: \(game.score)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Press Select to Play Again")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            game.resetGame()
            // Wire up click wheel to game
            vm.gameScrollHandler = { [weak game] direction in
                if direction > 0 {
                    game?.movePaddleRight()
                } else {
                    game?.movePaddleLeft()
                }
            }
            vm.gameSelectHandler = { [weak game] in
                guard let game else { return }
                if game.gameState == .ready {
                    game.launch()
                } else if game.gameState == .gameOver || game.gameState == .won {
                    game.restart()
                }
            }
        }
        .onDisappear {
            game.stopLoop()
            vm.gameScrollHandler = nil
            vm.gameSelectHandler = nil
        }
    }
}
