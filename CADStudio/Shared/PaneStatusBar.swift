import SwiftUI

struct PaneStatusBar<Controls: View>: View {
    var info = ""
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                controls
                Spacer(minLength: 8)
                Text(info)
                    .font(.system(size: 11).monospacedDigit())
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
    }
}
