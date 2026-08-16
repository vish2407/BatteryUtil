import AppKit
import ServiceManagement
import SwiftUI

@main
struct MenuBarBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var iconTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView: BatteryPanelView())
        hosting.sizingOptions = .preferredContentSize

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hosting

        updateStatusIcon()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let state = BatteryReader.shared.read()

        let bucket: Int
        switch state.percent {
        case ..<13: bucket = 0
        case ..<38: bucket = 25
        case ..<63: bucket = 50
        case ..<88: bucket = 75
        default: bucket = 100
        }

        let symbolName = state.isCharging ? "battery.100.bolt" : "battery.\(bucket)"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Battery \(state.percent)%")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            updateStatusIcon()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit BatteryUtil", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

struct BatteryPanelView: View {
    @State private var state = BatteryState(
        percent: 72,
        voltage: 11.9,
        current: 2.1,
        powerWatts: 24.9,
        healthPercent: 96,
        isCharging: true,
        isPluggedIn: true,
        timeToFullMinutes: 110,
        timeToEmptyMinutes: -1
    )
    @State private var refreshTimer: Timer?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    // Apple doesn't publish an exact wattage cutoff for "fast charge," but on
    // Mac laptops sustained draw above ~40W only happens with a fast-charge-
    // capable adapter, so that's the line we draw here.
    private var isFastCharging: Bool {
        state.isCharging && state.powerWatts > 40
    }

    private var batteryTint: Color {
        if isFastCharging { return .orange }
        if state.isCharging { return .green }
        switch state.percent {
        case ..<11: return .red
        case ..<21: return .yellow
        default: return .primary
        }
    }

    private var statusLabel: String {
        if isFastCharging { return "Fast Charging" }
        if state.isCharging { return "Charging" }
        return state.isPluggedIn ? "Plugged In" : "On Battery"
    }

    private var statusColor: Color {
        if isFastCharging { return .orange }
        if state.isCharging { return .green }
        return state.isPluggedIn ? .blue : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MacBook Battery")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    if state.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.caption2.weight(.bold))
                            .symbolEffect(.pulse, options: .repeating, isActive: isFastCharging)
                    }
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.3), value: statusLabel)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(state.percent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(batteryTint)
                            .frame(width: max(6, geo.size.width * CGFloat(state.percent) / 100))
                            .animation(.easeInOut(duration: 0.4), value: state.percent)
                            .animation(.easeInOut(duration: 0.4), value: isFastCharging)
                    }
                }
                .frame(height: 7)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatTile(label: "Power", value: String(format: "%.1f W", state.powerWatts), highlighted: isFastCharging)
                StatTile(label: "Voltage", value: String(format: "%.2f V", state.voltage))
                StatTile(label: "Current", value: String(format: "%.2f A", state.current))
                StatTile(label: "Health", value: state.healthPercent.map { "\($0)%" } ?? "—")
            }

            if state.isCharging {
                Divider()

                HStack {
                    Text("Time to full")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMinutes(state.timeToFullMinutes))
                        .fontWeight(.semibold)
                }
                .font(.callout)
            } else if !state.isPluggedIn {
                Divider()

                HStack {
                    Text("Time remaining")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(state.timeToEmptyMinutes >= 0 ? formatMinutes(state.timeToEmptyMinutes) : "Calculating…")
                        .fontWeight(.semibold)
                }
                .font(.callout)
            }

            Divider()

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.callout)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin.toggle()
                    }
                }
        }
        .padding(16)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            state = BatteryReader.shared.read()
            startTimer()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            state = BatteryReader.shared.read()
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(highlighted ? Color.orange.opacity(0.12) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(highlighted ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: highlighted)
    }
}

func formatMinutes(_ minutes: Int) -> String {
    if minutes <= 0 { return "Now" }
    let hours = minutes / 60
    let mins = minutes % 60
    return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
}
