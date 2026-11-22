import PolyplotCore
import SwiftUI

/// Settings → Advanced: things most learners never need, behind a warning. Changing the level or training
/// hours by hand, and Diagnostics. See docs/03-experience.md "Settings".
struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Group {
                Section {
                    Label("Make sure you know what you're doing before changing anything here.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 4)
                }
                if let profile = model.profile {
                    Section {
                        NavigationLink {
                            LevelSettingsView()
                        } label: {
                            LabeledContent("Level & training hours", value: "\(profile.band.rawValue) · \(Int(model.trainingHours.rounded())) h")
                        }
                    } header: {
                        Text(profile.pack.name)
                    } footer: {
                        Text("If your \(profile.pack.name) level or hours are off, set them by hand. You'll see what changes before anything does.")
                    }
                }
                Section {
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                } footer: {
                    Text("Checks for the app's features, to help track down a problem.")
                }
            }
            .polyplotRows()
        }
        .polyplotListBackground()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}
