import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            MetalView(model: model)
                .ignoresSafeArea()

            if let rendererError = model.rendererError {
                errorCard(rendererError)
            }
        }
        .background(Color(red: 0.01, green: 0.005, blue: 0.04))
    }

    private func errorCard(_ error: RendererError) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Metal initialization failed")
                .font(.headline)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
