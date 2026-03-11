import Foundation

// MARK: - CGS Types

typealias CGSConnectionID = Int
typealias CGSSpaceID = Int
typealias CGSWindowID = UInt32

// MARK: - CGS Private API Bindings

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?
