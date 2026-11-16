import Darwin
import Foundation
import IOKit

// MARK: - Settings

/// Color palette for a single appearance mode (light or dark).
/// All fields are optional — nil means "inherit from kantan's default style".
struct StyleColors: Decodable {
  var cpuLow: String?
  var cpuMedium: String?
  var cpuHigh: String?
  var cpuCritical: String?
  var thermalNominal: String?
  var thermalFair: String?
  var thermalSerious: String?
  var thermalCritical: String?

  private enum CodingKeys: String, CodingKey {
    case cpuLow = "cpu_low"
    case cpuMedium = "cpu_medium"
    case cpuHigh = "cpu_high"
    case cpuCritical = "cpu_critical"
    case thermalNominal = "thermal_nominal"
    case thermalFair = "thermal_fair"
    case thermalSerious = "thermal_serious"
    case thermalCritical = "thermal_critical"
  }

  static let empty = StyleColors()

  init() {}
}

/// Icon configuration for each menu section.
/// Values are icon names resolved by kantan's bundled icon font system
/// (e.g. "cpu", "server", "clock"). Raw Unicode glyphs are also accepted.
struct IconConfig: Decodable {
  var cpu: String
  var memory: String
  var disk: String
  var thermalNominal: String
  var thermalFair: String
  var thermalSerious: String
  var thermalCritical: String
  var uptime: String
  var load: String
  var activityMonitor: String

  private enum CodingKeys: String, CodingKey {
    case cpu
    case memory
    case disk
    case thermalNominal = "thermal_nominal"
    case thermalFair = "thermal_fair"
    case thermalSerious = "thermal_serious"
    case thermalCritical = "thermal_critical"
    case uptime
    case load
    case activityMonitor = "activity_monitor"
  }

  static let defaults = IconConfig(
    cpu: "cpu",
    memory: "script",
    disk: "device-floppy",
    thermalNominal: "thermometer",
    thermalFair: "thermometer",
    thermalSerious: "thermometer",
    thermalCritical: "thermometer",
    uptime: "clock",
    load: "graph",
    activityMonitor: "dashboard"
  )

  init(
    cpu: String, memory: String, disk: String,
    thermalNominal: String, thermalFair: String,
    thermalSerious: String, thermalCritical: String,
    uptime: String, load: String, activityMonitor: String
  ) {
    self.cpu = cpu
    self.memory = memory
    self.disk = disk
    self.thermalNominal = thermalNominal
    self.thermalFair = thermalFair
    self.thermalSerious = thermalSerious
    self.thermalCritical = thermalCritical
    self.uptime = uptime
    self.load = load
    self.activityMonitor = activityMonitor
  }

  init(from decoder: Decoder) throws {
    let d = IconConfig.defaults
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.cpu = container.setting(String.self, forKey: .cpu) ?? d.cpu
    self.memory = container.setting(String.self, forKey: .memory) ?? d.memory
    self.disk = container.setting(String.self, forKey: .disk) ?? d.disk
    self.thermalNominal =
      container.setting(String.self, forKey: .thermalNominal) ?? d.thermalNominal
    self.thermalFair =
      container.setting(String.self, forKey: .thermalFair) ?? d.thermalFair
    self.thermalSerious =
      container.setting(String.self, forKey: .thermalSerious) ?? d.thermalSerious
    self.thermalCritical =
      container.setting(String.self, forKey: .thermalCritical) ?? d.thermalCritical
    self.uptime = container.setting(String.self, forKey: .uptime) ?? d.uptime
    self.load = container.setting(String.self, forKey: .load) ?? d.load
    self.activityMonitor =
      container.setting(String.self, forKey: .activityMonitor) ?? d.activityMonitor
  }
}

/// Plugin settings decoded from the KANTAN_SETTINGS environment variable.
/// Style colors support light/dark variants matching kantan's convention.
struct Settings: Decodable {
  var format: String
  var colorTarget: String
  var style: StyleConfig?
  var icons: IconConfig
  var processCount: Int
  var showCores: Bool

  struct StyleConfig: Decodable {
    var light: StyleColors?
    var dark: StyleColors?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let light = container.setting(StyleColors.self, forKey: .light)
      let dark = container.setting(StyleColors.self, forKey: .dark)
      if light != nil || dark != nil {
        self.light = light
        self.dark = dark
      } else {
        // Flat style: same colours for both modes (theme handles mode switching)
        let flat = try StyleColors(from: decoder)
        self.light = flat
        self.dark = flat
      }
    }

    private enum CodingKeys: String, CodingKey {
      case light, dark
    }
  }

  private enum CodingKeys: String, CodingKey {
    case format
    case colorTarget = "color_target"
    case style
    case icons
    case processCount = "process_count"
    case showCores = "show_cores"
  }

  init() {
    self.format = "CPU {cpu}"
    self.colorTarget = "both"
    self.style = nil
    self.icons = .defaults
    self.processCount = 5
    self.showCores = false
  }

  init(from decoder: Decoder) throws {
    let defaults = Settings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.format = container.setting(String.self, forKey: .format) ?? defaults.format
    self.colorTarget =
      container.setting(String.self, forKey: .colorTarget) ?? defaults.colorTarget
    self.style = container.setting(StyleConfig.self, forKey: .style)
    self.icons = container.setting(IconConfig.self, forKey: .icons) ?? defaults.icons
    self.processCount =
      container.setting(Int.self, forKey: .processCount) ?? defaults.processCount
    self.showCores =
      container.setting(Bool.self, forKey: .showCores) ?? defaults.showCores
  }
}

/// Resolves the active color palette based on KANTAN_APPEARANCE and settings.
/// Only uses the palette matching the current appearance mode — no cross-mode fallback.
/// Missing colors inherit from kantan's default style cascade.
func resolveColors(settings: Settings) -> StyleColors {
  let appearance = ProcessInfo.processInfo.environment["KANTAN_APPEARANCE"] ?? "dark"
  let isDark = appearance == "dark"

  if isDark {
    return settings.style?.dark ?? .empty
  } else {
    return settings.style?.light ?? .empty
  }
}

// MARK: - CPU

/// Per-core tick counts from a single `host_processor_info` snapshot.
private struct CpuSnapshot {
  struct CoreTicks {
    let user: Int64
    let system: Int64
    let idle: Int64
    let nice: Int64
  }
  let cores: [CoreTicks]
}

/// Takes a single snapshot of per-core CPU tick counts.
private func sampleCpuTicks() -> CpuSnapshot? {
  var cpuInfo: processor_info_array_t?
  var numCpuInfo: mach_msg_type_number_t = 0
  var numCpus: natural_t = 0

  let result = host_processor_info(
    mach_host_self(),
    PROCESSOR_CPU_LOAD_INFO,
    &numCpus,
    &cpuInfo,
    &numCpuInfo
  )

  guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
  defer {
    vm_deallocate(
      mach_task_self_,
      vm_address_t(bitPattern: info),
      vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.stride)
    )
  }

  var cores: [CpuSnapshot.CoreTicks] = []
  for i in 0..<Int(numCpus) {
    let offset = Int(CPU_STATE_MAX) * i
    cores.append(
      CpuSnapshot.CoreTicks(
        user: Int64(info[offset + Int(CPU_STATE_USER)]),
        system: Int64(info[offset + Int(CPU_STATE_SYSTEM)]),
        idle: Int64(info[offset + Int(CPU_STATE_IDLE)]),
        nice: Int64(info[offset + Int(CPU_STATE_NICE)])
      ))
  }
  return CpuSnapshot(cores: cores)
}

/// Samples CPU ticks twice with a brief interval to compute live usage from the delta.
/// Returns (overall usage %, per-core usage). The sampling delay adds ~200ms to startup.
func cpuUsageSampled() -> (overall: Double, cores: [CoreUsage]) {
  guard let snap1 = sampleCpuTicks() else { return (0, []) }
  usleep(200_000)  // 200ms sample window
  guard let snap2 = sampleCpuTicks() else { return (0, []) }

  guard snap1.cores.count == snap2.cores.count else { return (0, []) }

  var totalDeltaUsed: Int64 = 0
  var totalDeltaAll: Int64 = 0
  var perCore: [CoreUsage] = []

  for i in 0..<snap1.cores.count {
    let a = snap1.cores[i]
    let b = snap2.cores[i]
    let dUser = b.user - a.user
    let dSystem = b.system - a.system
    let dIdle = b.idle - a.idle
    let dNice = b.nice - a.nice
    let dTotal = dUser + dSystem + dIdle + dNice
    let dUsed = dUser + dSystem + dNice

    totalDeltaUsed += dUsed
    totalDeltaAll += dTotal

    let corePct = dTotal > 0 ? Double(dUsed) / Double(dTotal) * 100.0 : 0
    perCore.append(CoreUsage(core: i, usage: corePct))
  }

  let overall = totalDeltaAll > 0 ? Double(totalDeltaUsed) / Double(totalDeltaAll) * 100.0 : 0
  return (overall, perCore)
}

struct CoreUsage {
  let core: Int
  let usage: Double
}

// MARK: - Memory

struct MemoryInfo {
  let totalGB: Double
  let usedGB: Double
  let wiredGB: Double
  let activeGB: Double
  let compressedGB: Double
  let freeGB: Double
  let pressurePercent: Double
}

func memoryInfo() -> MemoryInfo {
  let totalBytes = ProcessInfo.processInfo.physicalMemory
  let totalGB = Double(totalBytes) / 1_073_741_824

  var stats = vm_statistics64()
  var count = mach_msg_type_number_t(
    MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

  let result = withUnsafeMutablePointer(to: &stats) { ptr in
    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
      host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
    }
  }

  guard result == KERN_SUCCESS else {
    return MemoryInfo(
      totalGB: totalGB, usedGB: 0, wiredGB: 0,
      activeGB: 0, compressedGB: 0, freeGB: totalGB, pressurePercent: 0)
  }

  // Apple Silicon always uses 16384-byte pages; reading vm_kernel_page_size
  // directly triggers a Swift 6 concurrency error (shared mutable C global).
  let pageSize: Double = 16384
  let active = Double(stats.active_count) * pageSize / 1_073_741_824
  let wired = Double(stats.wire_count) * pageSize / 1_073_741_824
  let compressed = Double(stats.compressor_page_count) * pageSize / 1_073_741_824
  let free = Double(stats.free_count) * pageSize / 1_073_741_824
  let used = active + wired + compressed
  let pressure = totalGB > 0 ? used / totalGB * 100.0 : 0

  return MemoryInfo(
    totalGB: totalGB, usedGB: used, wiredGB: wired,
    activeGB: active, compressedGB: compressed, freeGB: free,
    pressurePercent: pressure)
}

// MARK: - Disk

struct DiskInfo {
  let totalGB: Double
  let usedGB: Double
  let freeGB: Double
  let usedPercent: Double
}

func diskInfo(path: String = "/") -> DiskInfo {
  let url = URL(fileURLWithPath: path)
  guard
    let values = try? url.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]),
    let total = values.volumeTotalCapacity,
    let available = values.volumeAvailableCapacityForImportantUsage
  else {
    return DiskInfo(totalGB: 0, usedGB: 0, freeGB: 0, usedPercent: 0)
  }

  let totalGB = Double(total) / 1_073_741_824
  let freeGB = Double(available) / 1_073_741_824
  let usedGB = totalGB - freeGB
  let pct = totalGB > 0 ? usedGB / totalGB * 100.0 : 0

  return DiskInfo(totalGB: totalGB, usedGB: usedGB, freeGB: freeGB, usedPercent: pct)
}

// MARK: - Thermal State

func thermalState() -> (name: String, level: Int) {
  switch ProcessInfo.processInfo.thermalState {
  case .nominal: return ("Nominal", 0)
  case .fair: return ("Fair", 1)
  case .serious: return ("Serious", 2)
  case .critical: return ("Critical", 3)
  @unknown default: return ("Unknown", 0)
  }
}

// MARK: - Uptime

/// When the Mac booted, from `kern.boottime`, or nil if it can't be read.
func bootTime() -> Date? {
  var boot = timeval()
  var size = MemoryLayout<timeval>.size
  guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
  return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1e6)
}

func uptimeString() -> String {
  // Time since boot, asleep included, unlike `systemUptime`.
  let uptime =
    bootTime().map { Date().timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime
  let hours = Int(uptime) / 3600
  let minutes = (Int(uptime) % 3600) / 60
  if hours >= 24 {
    let days = hours / 24
    let remainHours = hours % 24
    return "\(days)d \(remainHours)h"
  }
  return "\(hours)h \(minutes)m"
}

// MARK: - Load Average

func loadAverage() -> (one: Double, five: Double, fifteen: Double) {
  var loads: [Double] = [0, 0, 0]
  getloadavg(&loads, 3)
  return (loads[0], loads[1], loads[2])
}

// MARK: - Top Processes by CPU

struct ProcessStats {
  let pid: Int32
  let name: String
  let cpuPercent: Double
}

func topProcesses(count: Int = 5) -> [ProcessStats] {
  let pipe = Pipe()
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/ps")
  process.arguments = ["-Arcww", "-o", "pid,pcpu,comm", "-r"]
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice

  do {
    try process.run()
  } catch {
    return []
  }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()

  guard let output = String(data: data, encoding: .utf8) else { return [] }
  return topProcesses(
    in: output, count: count, excluding: ProcessInfo.processInfo.processIdentifier)
}

/// The first `count` processes in `ps -o pid,pcpu,comm` output, apart from
/// the process `excluding`, the plugin itself.
func topProcesses(in output: String, count: Int, excluding ownPID: Int32) -> [ProcessStats] {
  var results: [ProcessStats] = []
  for line in output.split(separator: "\n").dropFirst() {
    guard results.count < count else { break }
    let parts = line.split(separator: " ", maxSplits: 2)
    guard parts.count == 3,
      let pid = Int32(parts[0]),
      let cpu = Double(parts[1])
    else { continue }
    let name = String(parts[2])
    if pid == ownPID { continue }
    results.append(ProcessStats(pid: pid, name: name, cpuPercent: cpu))
  }
  return results
}

// MARK: - Helpers

func colorForCPU(_ pct: Double, colors: StyleColors) -> String? {
  if pct >= 80 { return colors.cpuCritical }
  if pct >= 50 { return colors.cpuHigh }
  if pct >= 30 { return colors.cpuMedium }
  return colors.cpuLow
}

func colorForThermal(_ level: Int, colors: StyleColors) -> String? {
  switch level {
  case 0: return colors.thermalNominal
  case 1: return colors.thermalFair
  case 2: return colors.thermalSerious
  default: return colors.thermalCritical
  }
}

func iconForThermal(_ level: Int, icons: IconConfig) -> String {
  switch level {
  case 0: return icons.thermalNominal
  case 1: return icons.thermalFair
  case 2: return icons.thermalSerious
  default: return icons.thermalCritical
  }
}

/// Build the plugin output `style` JSON node from a colour string, routing it
/// to `fg`, `icon.fg`, or `text.fg` based on the configured target.
func buildStyle(color: String, target: String) -> JSONValue {
  switch target {
  case "icon":
    return .object(["icon": .object(["fg": .string(color)])])
  case "text":
    return .object(["text": .object(["fg": .string(color)])])
  default:
    return .object(["fg": .string(color)])
  }
}

// MARK: - Main

func main() {
  let settings = loadSettings(defaults: Settings())
  let colors = resolveColors(settings: settings)
  let cpuSample = cpuUsageSampled()
  let cpu = cpuSample.overall
  let mem = memoryInfo()
  let disk = diskInfo()
  let thermal = thermalState()
  let uptime = uptimeString()
  let load = loadAverage()
  let procs = topProcesses(count: settings.processCount)

  let cpuStr = String(format: "%3.0f%%", cpu)
  let memUsedStr = String(format: "%.1f", mem.usedGB)
  let memTotalStr = String(format: "%.0f", mem.totalGB)
  let memStr = "\(memUsedStr)/\(memTotalStr) GB"
  let memPctStr = String(format: "%.0f%%", mem.pressurePercent)
  let diskUsedStr = String(format: "%.0f", disk.usedGB)
  let diskTotalStr = String(format: "%.0f", disk.totalGB)
  let diskStr = "\(diskUsedStr)/\(diskTotalStr) GB"
  let diskPctStr = String(format: "%.0f%%", disk.usedPercent)
  let loadStr = String(format: "%.2f %.2f %.2f", load.one, load.five, load.fifteen)

  let thermalIcon = iconForThermal(thermal.level, icons: settings.icons)
  let thermalColor = colorForThermal(thermal.level, colors: colors)
  let cpuColor = colorForCPU(cpu, colors: colors)

  // Build variables
  var variables: [String: String] = [
    "cpu": cpuStr,
    "cpu_pct": String(format: "%.2f", cpu / 100.0),
    "mem": memStr,
    "mem_pct": memPctStr,
    "mem_pct_norm": String(format: "%.2f", mem.pressurePercent / 100.0),
    "mem_used": "\(memUsedStr) GB",
    "mem_total": "\(memTotalStr) GB",
    "mem_wired": String(format: "%.1f GB", mem.wiredGB),
    "mem_active": String(format: "%.1f GB", mem.activeGB),
    "mem_compressed": String(format: "%.1f GB", mem.compressedGB),
    "mem_free": String(format: "%.1f GB", mem.freeGB),
    "disk": diskStr,
    "disk_pct": diskPctStr,
    "disk_pct_norm": String(format: "%.2f", disk.usedPercent / 100.0),
    "disk_used": "\(diskUsedStr) GB",
    "disk_total": "\(diskTotalStr) GB",
    "disk_free": String(format: "%.0f GB", disk.freeGB),
    "thermal": thermal.name,
    "thermal_icon": thermalIcon,
    "uptime": uptime,
    "load": loadStr,
    "load_1m": String(format: "%.2f", load.one),
    "load_5m": String(format: "%.2f", load.five),
    "load_15m": String(format: "%.2f", load.fifteen),
    "show_cores": settings.showCores ? "true" : "",
    "show_processes": !procs.isEmpty ? "true" : "",
  ]
  if let thermalColor {
    variables["thermal_color"] = thermalColor
  }

  // Build data collections
  var dataCollections: [String: [[String: String]]] = [:]

  if settings.showCores {
    dataCollections["cores"] = cpuSample.cores.map { core in
      [
        "core": "\(core.core)",
        "usage": String(format: "%.0f%%", core.usage),
        "usage_pct": String(format: "%.2f", core.usage / 100.0),
      ]
    }
  }

  if !procs.isEmpty {
    dataCollections["processes"] = procs.map { proc in
      [
        "name": proc.name,
        "cpu_pct": String(format: "%.1f%%", proc.cpuPercent),
      ]
    }
  }

  // Build view tree
  var viewChildren: [JSONValue] = []

  // Overview header
  viewChildren.append(header("Overview"))

  // CPU row
  viewChildren.append(
    hstack(children: [
      icon(settings.icons.cpu),
      text("CPU"),
      spacer(),
      text("{cpu}"),
    ]))

  // Memory row
  viewChildren.append(
    hstack(children: [
      icon(settings.icons.memory),
      text("Memory"),
      spacer(),
      text("{mem}"),
    ]))

  // Disk row
  viewChildren.append(
    hstack(children: [
      icon(settings.icons.disk),
      text("Disk"),
      spacer(),
      text("{disk}"),
    ]))

  // Thermal row
  viewChildren.append(
    hstack(children: [
      icon(thermalIcon),
      text("Thermal"),
      spacer(),
      text("{thermal}", color: thermalColor),
    ]))

  // Uptime row
  viewChildren.append(
    hstack(children: [
      icon(settings.icons.uptime),
      text("Uptime"),
      spacer(),
      text("{uptime}"),
    ]))

  // Load row
  viewChildren.append(
    hstack(children: [
      icon(settings.icons.load),
      text("Load"),
      spacer(),
      text("{load}"),
    ]))

  viewChildren.append(divider())

  // Conditional CPU Cores section
  viewChildren.append(
    conditional(
      variable: "show_cores",
      then: group(children: [
        header("CPU Cores"),
        foreach(
          items: "cores",
          child: hstack(children: [
            text("Core {core}"),
            spacer(),
            text("{usage}"),
          ])),
        divider(),
      ])))

  // Conditional Top Processes section
  viewChildren.append(
    conditional(
      variable: "show_processes",
      then: group(children: [
        header("Top Processes"),
        foreach(
          items: "processes",
          child: hstack(children: [
            text("{name}"),
            spacer(),
            text("{cpu_pct}"),
          ])),
        divider(),
      ])))

  // Activity Monitor action
  viewChildren.append(
    action(
      label: "Activity Monitor", icon: settings.icons.activityMonitor,
      command: "open -a 'Activity Monitor'"))

  let view = vstack(
    spacing: 8,
    padding: .object([
      "top": .double(12), "leading": .double(16), "bottom": .double(12), "trailing": .double(16),
    ]),
    frame: .object(["w": .int(300)]),
    children: viewChildren
  )

  // Format display value
  let displayValue = applyFormat(settings.format, variables: variables)

  let outputStyle = cpuColor.map { buildStyle(color: $0, target: settings.colorTarget) }

  let output = PluginOutput(
    value: displayValue,
    variables: variables,
    data: dataCollections,
    view: view,
    style: outputStyle
  )

  printJSON(output, pretty: true)
}

main()
