import Charts
import PracticeKit
import SwiftData
import SwiftUI

/// Per-item totals, weekly minutes, tempo history, recordings and notes.
struct ItemDetailView: View {
    @Bindable var item: PracticeItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var loggingTempo = false

    private var records: [SessionRecord] {
        (item.segments ?? []).map { segment in
            SessionRecord(startDate: segment.session?.startDate ?? segment.startDate,
                          activeDuration: segment.activeDuration,
                          segments: [SegmentRecord(itemID: item.id, category: item.category, duration: segment.activeDuration)])
        }
    }

    var body: some View {
        let stats = StatsCalculator()
        let now = Date()
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        List {
            Section {
                HStack {
                    total("All time", stats.itemTotal(item.id, records))
                    Divider()
                    total("This week", stats.itemTotal(item.id, records, in: week))
                    Divider()
                    total("This month", stats.itemTotal(item.id, records, in: month))
                }
                .padding(.vertical, 4)
                Button {
                    model.startSession(instrument: item.instrument, item: item)
                } label: {
                    Label("Practice This", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.sessionController.isActive)
            }

            Section("Minutes per week") {
                WeeklyItemChart(weeks: stats.itemWeeklyTotals(item.id, records, weeks: 12, now: now))
                    .frame(height: 160)
            }

            Section {
                TempoHistoryChart(entries: (item.tempoLog ?? []).sorted { $0.date < $1.date }, target: item.targetTempo)
                    .frame(height: 160)
                Button("Log Tempo", systemImage: "metronome") { loggingTempo = true }
            } header: {
                Text("Tempo")
            } footer: {
                if let target = item.targetTempo { Text("Target \(target) BPM") }
            }

            RecordingsSection(recordings: (item.recordings ?? []).sorted { $0.createdAt > $1.createdAt })

            Section("Status") {
                Picker("Status", selection: Binding(get: { item.status }, set: { item.status = $0; try? context.save() })) {
                    ForEach(ItemStatus.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Notes") {
                TextField("Fingerings, tricky bars, teacher feedback", text: $item.notes, axis: .vertical)
                    .lineLimit(3...12)
                    .onChange(of: item.notes) { item.updatedAt = Date() }
            }

            Section {
                Button(item.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                    item.status = item.isArchived ? .learning : .archived
                    try? context.save()
                }
                Button("Delete Item", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Archiving hides the item but keeps everything.")
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { ItemEditorView(item: item) }
        .sheet(isPresented: $loggingTempo) { TempoLogSheet(item: item) }
        .confirmationDialog("Delete \(item.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) {
                context.delete(item)
                try? context.save()
                model.storeDidChangeInBulk()
                dismiss()
            }
            Button("Archive Instead") { item.status = .archived; try? context.save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past sessions keep their time, but it won't be linked to this item anymore. Tempo history is deleted.")
        }
    }

    private func total(_ title: LocalizedStringKey, _ seconds: TimeInterval) -> some View {
        VStack(spacing: 4) {
            Text(DurationText.short(seconds)).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct WeeklyItemChart: View {
    let weeks: [DayTotal]

    var body: some View {
        Chart(weeks) { week in
            BarMark(x: .value("Week", week.day, unit: .weekOfYear), y: .value("Minutes", week.minutes))
                .foregroundStyle(.tint)
        }
        .chartYAxisLabel("min")
        .accessibilityChartDescriptor(BarChartDescriptor(
            title: String(localized: "Minutes per week"),
            points: weeks.map { ($0.day.formatted(.dateTime.month().day()), $0.minutes) },
            unit: String(localized: "minutes")))
    }
}

struct TempoHistoryChart: View {
    let entries: [TempoEntry]
    let target: Int?

    var body: some View {
        if entries.isEmpty {
            Text("No tempos logged yet. Save one from the metronome or tap Log Tempo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(entries) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value("BPM", entry.bpm))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.date), y: .value("BPM", entry.bpm))
                        .symbol(by: .value("Source", entry.source.rawValue.capitalized))
                }
                if let target {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Target").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYAxisLabel("BPM")
            .accessibilityChartDescriptor(BarChartDescriptor(
                title: String(localized: "Tempo history"),
                points: entries.map { ($0.date.formatted(.dateTime.month().day()), Double($0.bpm)) },
                unit: String(localized: "BPM")))
        }
    }
}

struct TempoLogSheet: View {
    let item: PracticeItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var bpm: Int

    init(item: PracticeItem) {
        self.item = item
        _bpm = State(initialValue: item.lastTempo ?? item.targetTempo ?? 80)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $bpm, in: 20...300) { Text("\(bpm) BPM").font(.title2.monospacedDigit()) }
            }
            .navigationTitle("Log Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(item.logTempo(bpm, source: .manual))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}

/// Text summary for VoiceOver's audio graph.
struct BarChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let points: [(String, Double)]
    let unit: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxValue = max(1, points.map(\.1).max() ?? 1)
        let x = AXCategoricalDataAxisDescriptor(title: String(localized: "Date"), categoryOrder: points.map(\.0))
        let y = AXNumericDataAxisDescriptor(title: unit, range: 0...maxValue, gridlinePositions: []) {
            "\(Int($0)) \(unit)"
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) })
        let total = points.map(\.1).reduce(0, +)
        return AXChartDescriptor(title: title, summary: String(localized: "Total \(Int(total)) \(unit)"),
                                 xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
