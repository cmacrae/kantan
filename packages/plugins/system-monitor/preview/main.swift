import Foundation

// Prints the states of the system-monitor module's preview: a quiet machine,
// a busy one, and one at its critical CPU and thermal levels.

/// A state of the preview: its name and the output the plugin prints in it.
struct PreviewState: Encodable {
  let name: String
  let output: PluginOutput
}

/// A reading with the CPU at `cpu` percent and the thermal state at `thermal`.
func sample(cpu: Double, thermal: (name: String, level: Int)) -> Sample {
  Sample(
    cpu: (cpu, []),
    memory: MemoryInfo(
      totalGB: 24, usedGB: 13.4, wiredGB: 2.6, activeGB: 8.1, compressedGB: 2.7, freeGB: 1.2,
      pressurePercent: 58),
    disk: DiskInfo(totalGB: 460, usedGB: 379, freeGB: 81, usedPercent: 82.4),
    thermal: thermal, uptime: "1d 4h", load: (2.45, 2.49, 2.53),
    processes: [
      ProcessStats(pid: 410, name: "WindowServer", cpuPercent: 24.2),
      ProcessStats(pid: 1022, name: "Emacs", cpuPercent: 16),
      ProcessStats(pid: 618, name: "Finder", cpuPercent: 3.2),
    ])
}

let settings = loadSettings(defaults: Settings())
let colors = resolveColors(settings: settings)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let preview = [
  "states": [
    PreviewState(
      name: "Quiet",
      output: render(
        sample(cpu: 12, thermal: ("Nominal", 0)), settings: settings, colors: colors)),
    PreviewState(
      name: "Busy",
      output: render(sample(cpu: 64, thermal: ("Fair", 1)), settings: settings, colors: colors)),
    PreviewState(
      name: "Critical",
      output: render(
        sample(cpu: 93, thermal: ("Critical", 3)), settings: settings, colors: colors)),
  ]
]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
