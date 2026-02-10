import SwiftUI
import Combine

struct ContentView: View {
    @State private var isGameStarted = false
    @State private var isShowingInstructions = false // 説明画面の状態
    @State private var counts: [String: (current: Int, total: Int)] = [
        "White": (0, 0), "Black": (0, 0), "Red": (0, 0), "Blue": (0, 0)
    ]
    
    // タイマー用の状態管理
    @State private var startTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // --- 背景設定 ---
            if !isGameStarted {
                // スタート画面：青空のグラデーション
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.4, green: 0.7, blue: 1.0),
                        Color(red: 0.8, green: 0.95, blue: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
            } else {
                // ゲーム中：落ち着いたベージュ系の背景
                Color(red: 1.0, green: 1.0, blue: 0.9)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // --- コンテンツレイヤー ---
            if !isGameStarted {
                if isShowingInstructions {
                    // 説明画面
                    // 説明画面
                    VStack(spacing: 50) { // 全体の間隔を広げた
                        Text("遊び方")
                            .font(.system(size: 100, weight: .black, design: .rounded)) // さらに巨大に
                            .foregroundColor(.orange)
                            .shadow(radius: 5)
                        
                        VStack(alignment: .leading, spacing: 60) { // リストの間隔を広げた
                            Text("1. AR空間のオブジェクトを指でつまみます。")
                            Text("2. 同じ色のエリアまで運んで離します。")
                            Text("3. 全ての色を仕分けたらミッション完了！")
                            Text("※矢印キーで視点を移動できます。")
                            Text("※掴むのは一つしかできないので両手一つずつ掴むことはできません。")
                        }
                        .font(.system(size: 45, weight: .bold, design: .rounded)) // 文字をかなり大きく
                        .foregroundColor(.orange) // 文字をオレンジに
                        .padding(60)
                        .background(Color.white.opacity(0.9)) // opacity 2.0は1.0と同じなので0.9程度が綺麗です
                        .cornerRadius(50)
                        .shadow(radius: 15)
                        
                        Text("Zキーを押して戻る")
                            .font(.system(size: 35, weight: .medium, design: .rounded))
                            .foregroundColor(.orange) // ここもオレンジに
                            .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // 画面いっぱいに広げる
                    .transition(.asymmetric(insertion: .scale, removal: .opacity)) // 出る時は大きく、消える時はふわっと
                } else {
                    // スタート画面
                    VStack(spacing: 60) { // タイトルと文字の間隔を少し広げた
                        Text("Hand Vision Sorter")
                            .font(.system(size: 120, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .shadow(radius: 5)
                        
                        VStack(spacing: 25) { // ガイド文字同士の間隔
                            Text("スペースキーを押して開始")
                                .font(.system(size: 50, weight: .bold, design: .rounded)) // 大幅にアップ
                            
                            Text("Zキーで遊び方を見る")
                                .font(.system(size: 35, weight: .medium, design: .rounded)) // こちらも大きく
                        }
                        .foregroundColor(.orange)
                        // 影をつけると、水色の背景でも文字がクッキリします
                        .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 2)
                        .phaseAnimator([0, 1]) { $0.opacity($1 == 0 ? 0.2 : 1.0) } animation: { _ in .easeInOut(duration: 0.8) }
                    }
                }
            } else {
                // ゲーム本編
                RealityViewContainer(counts: $counts)
                    .edgesIgnoringSafeArea(.all)
                
                GeometryReader { geo in
                    ZStack {
                        // 四隅のカウンター
                        CounterViewsGroup(counts: counts, size: geo.size)
                        
                        // 画面上部中央のタイマー
                        TimerDisplayView(time: elapsedTime)
                            .position(x: geo.size.width / 2, y: 50)
                        
                        // クリア表示
                        if isAllCleared {
                            VStack(spacing: 20) {
                                Text("MISSION COMPLETE!")
                                    .font(.system(size: 80, weight: .black, design: .rounded))
                                    .foregroundColor(.orange)
                                    .shadow(radius: 10)
                                
                                Text("Time: \(String(format: "%.1f", elapsedTime))s")
                                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange) // オレンジに変更
                                    .shadow(radius: 5)
                                
                                Text("10秒後にタイトルに戻ります...")
                                    .font(.headline)
                                    .foregroundColor(.yellow)
                            }
                            .transition(.scale)
                        }
                    }
                }
            }
        }
        // クリア状態を監視
        .onChange(of: isAllCleared) { oldValue, newValue in
            if newValue {
                Task {
                    try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                    resetGame()
                }
            }
        }
        .onReceive(timer) { _ in
            if isGameStarted && !isAllCleared {
                if let start = startTime {
                    elapsedTime = Date().timeIntervalSince(start)
                }
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
    }
    
    // クリア判定
    var isAllCleared: Bool {
        let total = counts.values.map { $0.total }.reduce(0, +)
        let current = counts.values.map { $0.current }.reduce(0, +)
        return total > 0 && current == total
    }
    
    // ゲームのリセット処理
    private func resetGame() {
        withAnimation(.easeInOut) {
            isGameStarted = false
            isShowingInstructions = false
            elapsedTime = 0
            startTime = nil
            counts = ["White": (0, 0), "Black": (0, 0), "Red": (0, 0), "Blue": (0, 0)]
        }
    }
    
    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Zキー (Key code: 6) の処理
            if event.keyCode == 6 {
                if !isGameStarted {
                    withAnimation {
                        isShowingInstructions.toggle()
                    }
                }
            }
            
            // Spaceキー (Key code: 49) の処理
            if event.keyCode == 49 {
                // 説明画面表示中でない時のみ開始
                if !isGameStarted && !isShowingInstructions {
                    withAnimation(.spring()) {
                        isGameStarted = true
                        startTime = Date()
                    }
                }
            }
            return event
        }
    }
}

// --- 補助的なビューの定義 ---

struct CounterViewsGroup: View {
    let counts: [String: (current: Int, total: Int)]
    let size: CGSize
    
    var body: some View {
        Group {
            CounterView(label: "白", current: counts["White"]?.current ?? 0, total: counts["White"]?.total ?? 0, color: .gray)
                .position(x: 100, y: 80)
            CounterView(label: "黒", current: counts["Black"]?.current ?? 0, total: counts["Black"]?.total ?? 0, color: .black)
                .position(x: size.width - 100, y: 80)
            CounterView(label: "赤", current: counts["Red"]?.current ?? 0, total: counts["Red"]?.total ?? 0, color: .red)
                .position(x: 100, y: size.height - 80)
            CounterView(label: "青", current: counts["Blue"]?.current ?? 0, total: counts["Blue"]?.total ?? 0, color: .blue)
                .position(x: size.width - 100, y: size.height - 80)
        }
    }
}
