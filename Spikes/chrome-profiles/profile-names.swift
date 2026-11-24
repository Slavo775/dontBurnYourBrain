// Spike helper for card #56. Not part of the app and not built by the check. See README.md.
//   swift profile-names.swift <Local State file>           the number of profiles and their directories
//   swift profile-names.swift <Local State file> --names   the same with each name, for a spike folder only
// Decodes `profile.info_cache.<directory>.name` and nothing else: the decoder skips every other key without
// keeping it, and the real file's info_cache also holds account emails and Google account names.
// `--names` is allowed only for a file whose path holds `/dontburn-chrome.`, the README's scratch folder, so a real
// profile name is never printed, however the path to Chrome's own folder is spelled.
// Exit status: 0 when the names were read, 1 when the file was refused or could not be read.
import Foundation

struct LocalState: Decodable {
    var profile: Profiles?
}

struct Profiles: Decodable {
    var infoCache: [String: Entry]?

    enum CodingKeys: String, CodingKey {
        case infoCache = "info_cache"
    }
}

struct Entry: Decodable {
    var name: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard (1 ... 2).contains(args.count), args.count == 1 || args[1] == "--names" else {
    fail("usage: swift profile-names.swift <Local State file> [--names]")
}

let file = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath()
if args.count == 2, !file.path.contains("/dontburn-chrome.") {
    fail("--names is only for a spike folder: a path that holds /dontburn-chrome.")
}

/// A Local State file is a few hundred kilobytes. Anything far larger is not one.
let limit = 32 << 20
guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
    fail("cannot read the size of the file")
}

guard size <= limit else { fail("the file is \(size) bytes, more than the \(limit) a Local State file can be") }

let data: Data
do { data = try Data(contentsOf: file) } catch {
    // On macOS 27 a read of Chrome's own folder fails here when the "App Data" permission is missing.
    fail("cannot read the file: \((error as NSError).domain) \((error as NSError).code)")
}

let state: LocalState
do { state = try JSONDecoder().decode(LocalState.self, from: data) } catch {
    fail("the file is not a Local State file Chrome wrote: \(type(of: error))")
}

let profiles = (state.profile?.infoCache ?? [:]).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
print("\(profiles.count) profiles, \(profiles.count(where: { $0.value.name?.isEmpty == false })) with a name")
for (directory, entry) in profiles {
    print(args.count == 2 ? "\(directory): \(entry.name ?? "(no name)")" : directory)
}
