import AppKit
import EventKit
import SwiftUI

struct CalendarComponentView: View {
    @ObservedObject var store: CalendarStore

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(spacing: 7) {
            calendarStrip

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            eventArea
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.start()
        }
    }

    private var calendarStrip: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(monthFormatter.string(from: store.selectedDate).capitalized)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minWidth: 36, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(store.visibleDates, id: \.self) { date in
                    dayButton(date)
                }
            }
        }
        .frame(height: 43)
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = Calendar.autoupdatingCurrent.isDate(
            date,
            inSameDayAs: store.selectedDate
        )

        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                store.select(date)
            }
        } label: {
            VStack(spacing: 3) {
                Text(weekdayFormatter.string(from: date).uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.72 : 0.34))

                Text(dayFormatter.string(from: date))
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Color.black : .white.opacity(0.62))
                    .frame(width: 22, height: 22)
                    .background(
                        isSelected ? Color(red: 0.17, green: 0.65, blue: 1) : .clear,
                        in: Circle()
                    )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDayLabel(date, isSelected: isSelected))
    }

    @ViewBuilder
    private var eventArea: some View {
        if store.isRequestingAccess {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Łączenie z Kalendarzem…")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !store.hasFullAccess {
            calendarAccessView
        } else if store.events.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
                Text("Brak wydarzeń na ten dzień")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(store.events) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private var calendarAccessView: some View {
        Button {
            if store.authorizationStatus == .notDetermined {
                store.requestAccess()
            } else if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            ) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                Text("Zezwól na dostęp do Kalendarza")
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(
                    Color(
                        red: event.color.red,
                        green: event.color.green,
                        blue: event.color.blue
                    )
                )
                .frame(width: 6, height: 6)

            Text(event.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(event.isAllDay ? "cały dzień" : timeFormatter.string(from: event.startDate))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 21)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    }

    private func accessibilityDayLabel(_ date: Date, isSelected: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .full
        let suffix = isSelected ? ", wybrany" : ""
        return formatter.string(from: date) + suffix
    }
}
