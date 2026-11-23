import Foundation

// MARK: - CGS Types

typealias CGSConnectionID = Int
typealias CGSSpaceID = Int
typealias CGSWindowID = UInt32

// MARK: - CGS Private API Bindings

/// The private function `name` as `type`, or nil when macOS doesn't have it.
/// It is looked for in every image loaded, as `RTLD_DEFAULT` (-2) has it.
private func privateFunction<T>(_ name: String, as type: T.Type) -> T? {
  dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
}

private let mainConnectionID = privateFunction(
  "CGSMainConnectionID", as: (@convention(c) () -> CGSConnectionID).self)
private let activeSpace = privateFunction(
  "CGSGetActiveSpace", as: (@convention(c) (CGSConnectionID) -> CGSSpaceID).self)
private let managedDisplaySpaces = privateFunction(
  "CGSCopyManagedDisplaySpaces",
  as: (@convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?).self)

/// The app's connection to the window server, or 0 without one.
func CGSMainConnectionID() -> CGSConnectionID {
  mainConnectionID?() ?? 0
}

/// The space now shown, or 0 when it can't be told.
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID {
  activeSpace?(cid) ?? 0
}

/// Each display and its spaces, or nil when they can't be told.
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray? {
  managedDisplaySpaces?(cid)?.takeRetainedValue()
}
