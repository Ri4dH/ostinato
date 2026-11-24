import PracticeKit
import SwiftData
import SwiftUI

/// Drone on any of the 12 notes; mixes with the metronome and keeps playing in the background.
struct DroneView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]

    private var drone: DroneEngine { model.audio.drone }

    private var transposition: Int {
        let id = model.sessionController.active?.instrument?.id ?? settings.lastInstrumentID
        return instruments.first { $0.id == id }?.transposition ?? 0
    }

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        @Bindable var drone = drone
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<12, id: \.self) { pitch in
                        Button {
                            drone.settings.pitchClass = pitch
                            if !drone.isPlaying { drone.start() }
                        } label: {
                            Text(NoteMath.names[pitch])
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(drone.settings.pitchClass == pitch ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
                        .accessibilityAddTraits(drone.settings.pitchClass == pitch ? .isSelected : [])
                    }
                }

                Button {
                    drone.toggle()
                } label: {
                    Label(drone.isPlaying ? "Stop" : "Play", systemImage: drone.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.glassProminent)

                VStack(spacing: 14) {
                    Stepper("Octave \(drone.settings.octave)", value: $drone.settings.octave, in: 1...6)
                    Picker("Voicing", selection: $drone.settings.voicing) {
                        ForEach(DroneVoicing.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Sound", selection: $drone.settings.timbre) {
                        ForEach(DroneTimbre.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if transposition != 0 {
                        Toggle("Concert pitch", isOn: $drone.settings.useConcertPitch)
                    }
                    HStack {
                        Image(systemName: "speaker.fill").accessibilityHidden(true)
                        Slider(value: $drone.settings.volume, in: 0...1) { Text("Volume") }
                        Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                    }
                    Text("A4 = \(Int(settings.a4Reference)) Hz. Change it in the tuner.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Drone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            drone.settings.a4 = settings.a4Reference
            drone.settings.transposition = transposition
        }
        .onChange(of: drone.settings) { _, new in settings.drone = new }
    }
}
