import SwiftUI

// Message bref en haut de l'écran (« Enregistré »), comme TikTok : pastille grise, effacée après 2 s.
// L'effacement est programmé au changement du message, pas par une tâche de la pastille : celle-ci est recréée (et sa
// tâche annulée) quand l'écran revient au premier plan, ce qui effaçait le message aussitôt.
extension View {
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.3, opacity: 0.92), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("toast")
            }
        }
        .onChange(of: message.wrappedValue) { _, text in
            guard let text else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                if message.wrappedValue == text { withAnimation { message.wrappedValue = nil } }
            }
        }
    }
}
