import SwiftUI

#if DEBUG
    // Écran « Expériences » (ADR-077), build Debug seulement, en bas de Paramètres et confidentialité : pour chaque
    // expérience du catalogue, le groupe tiré sur cet iPhone et une variante à forcer (« Automatique » : PostHog).
    // Une variante forcée n'est jamais exposée ni gardée. Un argument de lancement `-experiment.<flag> <variante>`
    // l'emporte sur ce choix.
    struct ExperimentsDebugView: View {
        @Environment(AnalyticsModel.self) private var analytics
        @State private var isConfirmingReset = false

        var body: some View {
            List {
                ForEach(Experiments.all) { experiment in
                    Section {
                        Picker("Variante", selection: forcedBinding(experiment)) {
                            Text("Automatique (PostHog)").tag(String?.none)
                            ForEach(experiment.variants, id: \.self) { variant in
                                Text(variant == experiment.control ? "\(variant) (témoin)" : variant).tag(String?.some(variant))
                            }
                        }
                        .accessibilityIdentifier("experiments.\(experiment.flag)")
                        LabeledContent("Groupe tiré", value: analytics.storedVariant(of: experiment) ?? "pas encore")
                    } header: {
                        Text(experiment.title)
                    } footer: {
                        Text("\(experiment.summary)\nFlag : \(experiment.flag)")
                    }
                }
                Section {
                    Button("Oublier les groupes tirés", role: .destructive) { isConfirmingReset = true }
                        .confirmationDialog("Oublier les groupes tirés ?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                            Button("Oublier", role: .destructive) { analytics.clearExperimentAssignments() }
                        } message: {
                            Text("Chaque expérience sera tirée de nouveau la prochaine fois qu’elle s’affiche.")
                        }
                } footer: {
                    Text(
                        analytics.isEnabled
                            ? "Mesure d’audience activée." : "Mesure d’audience refusée : sans variante forcée, tout le monde est témoin.")
                }
            }
            .navigationTitle("Expériences")
            .navigationBarTitleDisplayMode(.inline)
        }

        private func forcedBinding(_ experiment: Experiment) -> Binding<String?> {
            Binding(
                get: { analytics.forcedVariant(of: experiment) },
                set: { analytics.setForcedVariant($0, of: experiment) }
            )
        }
    }
#endif
