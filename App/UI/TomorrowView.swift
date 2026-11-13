import SwiftUI
import UIKit
import WakelatchCore

/// Home: the next morning as a dial, the two times, repeat days and challenges.
struct TomorrowView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: TimeField?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MorningDial(dates: model.nextMorning?.rings.map(\.date) ?? [], latched: model.settings.enabled)
                        .frame(maxWidth: 260)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    TimesRow(times: model.settings.times, editing: $editing)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    summary
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !model.alarmsAuthorized {
                    Section {
                        Label("Alarms are off for Wakelatch. Turn them on in Settings.", systemImage: "exclamationmark.triangle")
                        Button("Open Settings") { openSystemSettings() }
                    }
                }

                Section {
                    Toggle("Alarm on", isOn: Binding(get: { model.settings.enabled },
                                                     set: { on in model.update { $0.enabled = on } }))
                        .tint(Theme.graphite)
                        .accessibilityIdentifier("tomorrow.enabled")
                    RepeatDaysRow(days: model.settings.repeatDays) { days in model.update { $0.repeatDays = days } }
                } footer: {
                    Text(repeatFooter)
                }

                Section("Challenges") {
                    NavigationLink(value: ChallengeSlot.snooze) {
                        LabeledContent("Before the deadline", value: model.settings.snoozeChallenge.title)
                    }
                    NavigationLink(value: ChallengeSlot.deadline) {
                        LabeledContent("At the deadline", value: model.settings.deadlineChallenge.title)
                    }
                }

                if let history = model.historyLine {
                    Section { Text(history).foregroundStyle(Theme.graphite) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.enamel)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .navigationTitle(title)
            .navigationDestination(for: ChallengeSlot.self) { ChallengePickerView(slot: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("tomorrow.settings")
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button("Bedside mode") { model.bedside = true }
                    .buttonStyle(.slab)
                    .disabled(model.nextMorning == nil)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("tomorrow.bedside")
            }
            .sheet(item: $editing) { field in TimeSheet(field: field).presentationDetents([.medium]) }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var title: String {
        guard let day = model.nextMorning?.day else { return "Alarm off" }
        if model.calendar.isDateInToday(day) { return "This morning" }
        if model.calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    @ViewBuilder private var summary: some View {
        if let problem = model.timesProblem {
            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.face)
        } else if let plan = model.nextMorning?.rings, let first = plan.first, let last = plan.last {
            Text("Rings from \(first.date.shortTime) to \(last.date.shortTime) if you don't solve it. \(plan.count) rings.")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.graphite)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        } else {
            Text("No alarm is set.")
                .font(.subheadline)
                .foregroundStyle(Theme.graphite)
                .frame(maxWidth: .infinity)
        }
    }

    private var repeatFooter: String {
        model.settings.repeatDays.isEmpty ? "Rings once, then turns off." : "Rings on the highlighted days."
    }
}

enum TimeField: String, Identifiable {
    case ideal, deadline
    var id: String { rawValue }
    var title: String { self == .ideal ? "Ideal" : "Deadline" }
}

enum ChallengeSlot: Hashable {
    case snooze, deadline
}

/// The two times, large, side by side.
private struct TimesRow: View {
    let times: WakeTimes
    @Binding var editing: TimeField?

    var body: some View {
        HStack(spacing: 12) {
            cell(.ideal, times.ideal, caption: "When you'd like to be up")
            cell(.deadline, times.deadline, caption: "When you must be up")
        }
    }

    private func cell(_ field: TimeField, _ time: ClockTime, caption: String) -> some View {
        Button { editing = field } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(field.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                }
                .foregroundStyle(Theme.graphite)
                Text(time.formatted)
                    .font(.system(.largeTitle, design: .default).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.face)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(caption).font(.caption).foregroundStyle(Theme.graphite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.face.opacity(0.08), in: .rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(field.title), \(time.formatted). \(caption).")
        .accessibilityHint("Changes the time")
        .accessibilityIdentifier("tomorrow.\(field.rawValue)")
    }
}

/// S M T W T F S toggles.
private struct RepeatDaysRow: View {
    let days: Set<Int>
    let onChange: (Set<Int>) -> Void

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        let first = Calendar.current.firstWeekday
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (first - 1 + offset) % 7 + 1
                let on = days.contains(weekday)
                Button {
                    var next = days
                    if on { next.remove(weekday) } else { next.insert(weekday) }
                    onChange(next)
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? Theme.face : Theme.graphite)
                        .background(Theme.face.opacity(on ? 0.16 : 0.04), in: .rect(cornerRadius: Theme.radius))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .strokeBorder(on ? Theme.face : Color.clear, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Wheel picker for one of the two times.
struct TimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let field: TimeField
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker(field.title, selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Text(field == .ideal ? "Soft nudges start 20 minutes before this, and the latch starts here."
                                     : "From this time the alarm rings every minute and Stop no longer snoozes.")
                    .font(.footnote)
                    .foregroundStyle(Theme.graphite)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.accessibilityIdentifier("time.done")
                }
            }
        }
        .onAppear { date = (field == .ideal ? model.settings.times.ideal : model.settings.times.deadline).date }
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let time = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        model.update {
            switch field {
            case .ideal:
                // Keep the window the same length when Ideal moves.
                let window = $0.times.windowMinutes
                $0.times.ideal = time
                let end = (time.minutes + window) % (24 * 60)
                $0.times.deadline = ClockTime(hour: end / 60, minute: end % 60)
            case .deadline:
                $0.times.deadline = time
            }
        }
        dismiss()
    }
}

/// The station dial drawn over one morning: first ring at twelve, last ring just before it.
struct MorningDial: View {
    let dates: [Date]
    var latched = true
    /// The ring sounding now, drawn in signal red.
    var activeIndex: Int?

    var body: some View {
        StationDial(rings: fractions, latched: latched && !dates.isEmpty, activeRing: activeIndex)
            .accessibilityLabel(dates.isEmpty ? "No alarm set" : "\(dates.count) rings, \(dates.first!.shortTime) to \(dates.last!.shortTime)")
    }

    private var fractions: [Double] {
        guard let first = dates.first, let last = dates.last, last > first else {
            return dates.isEmpty ? [] : [0]
        }
        let span = last.timeIntervalSince(first)
        return dates.map { 0.92 * $0.timeIntervalSince(first) / span }
    }
}

extension ClockTime {
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    var formatted: String { date.shortTime }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

@MainActor
func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
