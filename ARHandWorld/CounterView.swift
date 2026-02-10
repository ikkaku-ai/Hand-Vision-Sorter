import SwiftUI

struct CounterView: View {
    let label: String
    let current: Int
    let total: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.headline).foregroundColor(color)
            Text("\(current) / \(total)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
        }
        .padding(15)
        .background(Color.white.opacity(0.7))
        .cornerRadius(15)
        .shadow(radius: 5)
    }
}
