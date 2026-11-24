import PracticeKit
import SwiftData
import SwiftUI

/// Recordings list: play, rename, share, delete.
struct RecordingsSection: View {
    let recordings: [Recording]
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var playing: Recording?
    @State private var renaming: Recording?
    @State private var newTitle = ""
    @State private var deleting: Recording?

    var body: some View {
        Section("Recordings") {
            if recordings.isEmpty {
                Text("Tap Record during a session to hear how it sounds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(recordings) { recording in
                RecordingRow(recording: recording, availability: model.recordingFiles.availability(of: recording)) {
                    playing = recording
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = recording }
                    Button("Rename", systemImage: "pencil") {
                        newTitle = recording.title
                        renaming = recording
                    }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        newTitle = recording.title
                        renaming = recording
                    }
                    if case .ready(let url) = model.recordingFiles.availability(of: recording) {
                        ShareLink(item: url, preview: SharePreview(recording.title.isEmpty ? url.lastPathComponent : recording.title))
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = recording }
                }
            }
        }
        .sheet(item: $playing) { RecordingPlayerSheet(recording: $0) }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                renaming?.title = String(newTitle.prefix(200))
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this recording?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { recording in
            Button("Delete Recording", role: .destructive) { model.recordingFiles.delete(recording, in: context) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The audio file is removed from all your devices.")
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    let availability: RecordingFiles.Availability
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(availability == .onAnotherDevice ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title.isEmpty ? String(localized: "Recording") : recording.title)
                        .foregroundStyle(.primary)
                    Text("\(recording.createdAt, format: .dateTime.month().day().hour().minute()) · \(DurationText.clock(recording.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if availability == .onAnotherDevice {
                        Text("Stored on another device").font(.caption).foregroundStyle(.secondary)
                    } else if availability == .downloading {
                        Text("Downloading from iCloud…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(!isReady)
        .accessibilityHint(isReady ? Text("Plays the recording") : Text(""))
    }

    private var isReady: Bool {
        if case .ready = availability { return true }
        return false
    }

    private var icon: String {
        switch availability {
        case .ready: "play.circle.fill"
        case .downloading: "icloud.and.arrow.down"
        case .onAnotherDevice: "iphone.gen3.slash"
        }
    }
}

/// Playback with scrubbing and 0.5×–1.0× pitch-preserved speed.
struct RecordingPlayerSheet: View {
    let recording: Recording
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scrubTime: TimeInterval?
    @State private var loadFailed = false

    private var player: RecordingPlayer { model.audio.player }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if loadFailed {
                    ContentUnavailableView("Can't play this recording", systemImage: "waveform.slash",
                                           description: Text("The file may still be downloading. Try again in a moment."))
                } else {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        let current = scrubTime ?? player.currentTime
                        VStack(spacing: 8) {
                            Slider(value: Binding(get: { current }, set: { scrubTime = $0 }),
                                   in: 0...max(player.duration, 0.1)) {
                                Text("Position")
                            } onEditingChanged: { editing in
                                if !editing, let time = scrubTime {
                                    player.seek(to: time)
                                    scrubTime = nil
                                }
                            }
                            .accessibilityValue(DurationText.timerSpoken(current))
                            HStack {
                                Text(DurationText.clock(current))
                                Spacer()
                                Text(DurationText.clock(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        player.togglePlay()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.largeTitle)
                            .frame(width: 80, height: 80)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Picker("Speed", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                        Text("0.5×").tag(Float(0.5))
                        Text("0.75×").tag(Float(0.75))
                        Text("1×").tag(Float(1))
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding()
            .navigationTitle(recording.title.isEmpty ? String(localized: "Recording") : recording.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if case .ready(let url) = model.recordingFiles.availability(of: recording) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url, preview: SharePreview(recording.title.isEmpty ? url.lastPathComponent : recording.title))
                    }
                }
            }
            .onAppear {
                guard case .ready(let url) = model.recordingFiles.availability(of: recording) else {
                    loadFailed = true
                    return
                }
                do { try player.load(url) } catch { loadFailed = true }
            }
            .onDisappear { player.stop() }
        }
        .presentationDetents([.medium])
    }
}
