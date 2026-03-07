import SwiftUI
import IOKit.ps

// MARK: - Battery Detail Popup

struct BatteryPopupView: View {
    let fgColor: Color
    let bgColor: Color

    var body: some View {
        let status = Self.readBatteryStatus()

        VStack(alignment: .leading, spacing: 6) {
            Text(status.stateText)
                .font(.system(size: 11))
                .foregroundStyle(fgColor.opacity(0.5))

            Text(status.isAvailable ? "\(status.level)%" : "Unavailable")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(fgColor)

            if status.isAvailable {
                ProgressBarView(value: Double(status.level) / 100.0, color: status.barColor, fgColor: fgColor)
            }
        }
        .padding(16)
        .frame(minWidth: 200, alignment: .leading)
    }

    private struct BatteryStatus {
        let level: Int
        let isCharging: Bool
        let isPluggedIn: Bool
        let isAvailable: Bool

        var stateText: String {
            if isCharging { return "Charging" }
            if isPluggedIn { return "Plugged In" }
            return "Battery"
        }

        var barColor: Color {
            if isCharging { return .green }
            if level <= 10 { return .red }
            if level <= 20 { return .yellow }
            return .green
        }
    }

    private static func readBatteryStatus() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFDictionary] else {
            return BatteryStatus(level: 0, isCharging: false, isPluggedIn: false, isAvailable: false)
        }
        for source in sources {
            guard let sourceDict = source as? [String: Any],
                  let currentCapacity = sourceDict[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = sourceDict[kIOPSMaxCapacityKey as String] as? Int,
                  maxCapacity > 0 else { continue }
            let level = (currentCapacity * 100) / maxCapacity
            let isCharging = (sourceDict[kIOPSIsChargingKey as String] as? Bool) ?? false
            let powerSourceState = sourceDict[kIOPSPowerSourceStateKey as String] as? String
            let isPluggedIn = (powerSourceState == kIOPSACPowerValue as String)
            return BatteryStatus(level: level, isCharging: isCharging, isPluggedIn: isPluggedIn, isAvailable: true)
        }
        return BatteryStatus(level: 0, isCharging: false, isPluggedIn: false, isAvailable: false)
    }
}

// MARK: - Volume Detail Popup

struct VolumePopupView: View {
    let fgColor: Color
    let bgColor: Color

    @State private var volume: Double = 0
    @State private var isMuted: Bool = false
    @State private var devices: [AudioOutputDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mute toggle + volume display
            HStack(spacing: 8) {
                Text(isMuted ? "\u{f026}" : "\u{f028}")
                    .font(.system(size: 14))
                    .foregroundStyle(fgColor.opacity(isMuted ? 0.4 : 0.8))
                    .frame(width: 20)
                    .onTapGesture {
                        isMuted.toggle()
                        VolumeConfig.setMuted(isMuted)
                    }

                VolumeSliderView(
                    value: $volume,
                    fgColor: fgColor,
                    onChanged: { newValue in
                        if isMuted {
                            isMuted = false
                            VolumeConfig.setMuted(false)
                        }
                        VolumeConfig.setVolume(Float(newValue))
                    }
                )

                Text(isMuted ? "Muted" : "\(Int(volume * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(fgColor.opacity(0.6))
                    .frame(width: 44, alignment: .trailing)
            }

            Divider()
                .background(fgColor.opacity(0.15))

            // Output devices
            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(fgColor.opacity(0.5))
                    .padding(.horizontal, 4)

                ForEach(devices) { device in
                    AudioDeviceRowView(device: device, fgColor: fgColor) {
                        VolumeConfig.setDefaultOutputDevice(device.id)
                        devices = VolumeConfig.listOutputDevices()
                        let status = VolumeConfig.readVolumeStatus()
                        volume = Double(status.volume)
                        isMuted = status.isMuted
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260, alignment: .leading)
        .onAppear {
            let status = VolumeConfig.readVolumeStatus()
            volume = Double(status.volume)
            isMuted = status.isMuted
            devices = VolumeConfig.listOutputDevices()
        }
    }
}

struct VolumeSliderView: View {
    @Binding var value: Double
    let fgColor: Color
    let onChanged: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fgColor.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(fgColor)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = min(max(Double(gesture.location.x / geo.size.width), 0), 1)
                        value = newValue
                        onChanged(newValue)
                    }
            )
        }
        .frame(height: 8)
    }
}

struct AudioDeviceRowView: View {
    let device: AudioOutputDevice
    let fgColor: Color
    let onSelect: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(device.isDefault ? "\u{2713}" : " ")
                .font(.system(size: 13, weight: .medium).monospaced())
                .foregroundStyle(fgColor)
                .frame(width: 16)

            Text(device.name)
                .font(.system(size: 13))
                .foregroundStyle(fgColor)
                .lineLimit(1)

            Spacer()

            if !device.transportLabel.isEmpty {
                Text(device.transportLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(fgColor.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? fgColor.opacity(0.1) : .clear)
        )
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
    }
}

// MARK: - WiFi Detail Popup

struct WiFiPopupView: View {
    let fgColor: Color
    let bgColor: Color

    var body: some View {
        let status = WiFiConfig.readWiFiStatus()

        VStack(alignment: .leading, spacing: 6) {
            Text(status.isConnected ? "Connected" : "Disconnected")
                .font(.system(size: 11))
                .foregroundStyle(fgColor.opacity(0.5))

            Text(status.ssid ?? "Not connected")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(fgColor)

            if status.isConnected {
                let barColor: Color = status.signalQuality >= 0.66 ? .green :
                                      status.signalQuality >= 0.33 ? .yellow : .red

                Text("Signal")
                    .font(.system(size: 11))
                    .foregroundStyle(fgColor.opacity(0.5))

                ProgressBarView(value: Double(status.signalQuality), color: barColor, fgColor: fgColor)

                Text("RSSI: \(status.rssi) dBm")
                    .font(.system(size: 11))
                    .foregroundStyle(fgColor.opacity(0.5))
            }
        }
        .padding(16)
        .frame(minWidth: 200, alignment: .leading)
    }
}

// MARK: - Calendar Popup

struct CalendarPopupView: View {
    let fgColor: Color
    let bgColor: Color

    var body: some View {
        let now = Date()
        let cal = Calendar.current

        VStack(alignment: .leading, spacing: 8) {
            Text(monthYearString(date: now))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(fgColor)

            CalendarGridView(fgColor: fgColor, bgColor: bgColor, calendar: cal, date: now)
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }

    private func monthYearString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

struct CalendarGridView: View {
    let fgColor: Color
    let bgColor: Color
    let calendar: Calendar
    let date: Date

    private let cellSize: CGFloat = 28

    var body: some View {
        let today = calendar.component(.day, from: date)
        let info = calendarInfo()

        VStack(spacing: 0) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(info.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(fgColor.opacity(0.5))
                        .frame(width: cellSize, height: 20)
                }
            }

            // Day grid
            ForEach(0..<info.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let dayNumber = cellIndex - info.blanks + 1

                        if dayNumber >= 1 && dayNumber <= info.totalDays {
                            let isToday = dayNumber == today
                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(fgColor)
                                        .frame(width: 22, height: 22)
                                }
                                Text("\(dayNumber)")
                                    .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(isToday ? bgColor : fgColor)
                            }
                            .frame(width: cellSize, height: cellSize)
                        } else {
                            Color.clear
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private struct CalendarInfo {
        let weekdaySymbols: [String]
        let blanks: Int
        let totalDays: Int
        let rows: Int
    }

    private func calendarInfo() -> CalendarInfo {
        let weekdays = calendar.veryShortWeekdaySymbols
        let firstIdx = calendar.firstWeekday - 1
        let reordered = Array(weekdays[firstIdx...]) + Array(weekdays[..<firstIdx])

        guard let range = calendar.range(of: .day, in: .month, for: date),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return CalendarInfo(weekdaySymbols: reordered, blanks: 0, totalDays: 0, rows: 0)
        }

        let startWeekday = calendar.component(.weekday, from: firstOfMonth)
        let blanks = (startWeekday - calendar.firstWeekday + 7) % 7
        let totalDays = range.count
        let totalCells = blanks + totalDays
        let rows = (totalCells + 6) / 7

        return CalendarInfo(weekdaySymbols: reordered, blanks: blanks, totalDays: totalDays, rows: rows)
    }
}

// MARK: - Shared Progress Bar

struct ProgressBarView: View {
    let value: Double
    let color: Color?
    let fgColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fgColor.opacity(0.2))

                if value > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color ?? fgColor)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
        }
        .frame(height: 6)
    }
}
