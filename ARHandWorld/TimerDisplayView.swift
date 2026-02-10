import SwiftUI

struct TimerDisplayView: View {
    let time: TimeInterval
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch")
            Text(String(format: "%.1f", time))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(20)
    }
}
