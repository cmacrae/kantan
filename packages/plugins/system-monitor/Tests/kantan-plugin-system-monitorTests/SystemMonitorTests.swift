import Foundation
import Testing

@testable import kantan_plugin_system_monitor

struct TopProcessesTests {
  private let output = """
      PID  %CPU COMM
      101  42.0 WindowServer
      202  12.5 Safari
      303   1.0 Finder
    """

  @Test func testListsAtMostCountProcesses() {
    #expect(topProcesses(in: output, count: 2).map(\.name) == ["WindowServer", "Safari"])
    #expect(topProcesses(in: output, count: 0).isEmpty)
  }
}
