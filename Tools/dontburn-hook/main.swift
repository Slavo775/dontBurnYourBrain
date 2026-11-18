import Foundation

// Both come from the Info.plist built into the binary, from project.yml.
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
print("dontburn-hook \(version) (\(build))")
