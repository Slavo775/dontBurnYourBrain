@testable import DontBurnCore
import Foundation
import Testing

/// A made-up home folder with a profile in it, and a stand-in folder beside it.
private struct Homes {
    let home: String
    let standIn: String

    init(_ temporary: TemporaryFolder) throws {
        home = try temporary.make("people/acme")
        try temporary.make("people/acme/.claude-acme")
        standIn = try temporary.make("standin")
    }
}

@Test func `a stand-in beside the home folder is used, resolved`() throws {
    try withTemporaryFolder { temporary in
        let homes = try Homes(temporary)

        #expect(ProfileStandIn.folder(from: homes.standIn, home: homes.home) == FolderPath.resolved(homes.standIn))
        let resolved = FolderPath.resolved(homes.standIn)
        #expect(ProfileStandIn.folder(from: homes.standIn + "/", home: homes.home) == resolved)
    }
}

@Test func `the home folder, a folder in it or one that holds it is refused as a stand-in`() throws {
    try withTemporaryFolder { temporary in
        let homes = try Homes(temporary)
        let refused = [
            homes.home,
            homes.home + "/",
            homes.home + "/.claude-acme",
            homes.home + "/not-made-yet",
            temporary.path("standin/../people/acme/.claude-acme"),
            temporary.path("people"),
            temporary.path(""),
            "/",
            FolderPath.resolved(homes.home) + "/.claude-acme",
        ]

        for raw in refused {
            #expect(ProfileStandIn.folder(from: raw, home: homes.home) == nil, "\(raw)")
        }
    }
}

@Test func `another case of the home folder's name is refused where the disk ignores case`() throws {
    try withTemporaryFolder { temporary in
        let homes = try Homes(temporary)
        let variant = temporary.path("PEOPLE/ACME/.claude-acme")
        // On a disk that tells case apart, the variant is another folder, which may be a stand-in.
        guard FileManager.default.fileExists(atPath: variant) else { return }

        #expect(ProfileStandIn.folder(from: variant, home: homes.home) == nil)
    }
}

@Test func `a link outside the home folder that leads into it or above it is refused`() throws {
    try withTemporaryFolder { temporary in
        let homes = try Homes(temporary)
        let intoProfile = temporary.path("acme-link")
        let aboveHome = temporary.path("people-link")
        let profile = homes.home + "/.claude-acme"
        try FileManager.default.createSymbolicLink(atPath: intoProfile, withDestinationPath: profile)
        try FileManager.default.createSymbolicLink(atPath: aboveHome, withDestinationPath: temporary.path("people"))

        #expect(ProfileStandIn.folder(from: intoProfile, home: homes.home) == nil)
        #expect(ProfileStandIn.folder(from: aboveHome, home: homes.home) == nil)
    }
}

@Test func `a home folder reached through a link is refused in both its spellings`() throws {
    try withTemporaryFolder { temporary in
        let homes = try Homes(temporary)
        let linkedHome = temporary.path("home-link")
        try FileManager.default.createSymbolicLink(atPath: linkedHome, withDestinationPath: homes.home)

        #expect(ProfileStandIn.folder(from: homes.home + "/.claude-acme", home: linkedHome) == nil)
        #expect(ProfileStandIn.folder(from: linkedHome + "/.claude-acme", home: linkedHome) == nil)
        #expect(ProfileStandIn.folder(from: homes.standIn, home: linkedHome) == FolderPath.resolved(homes.standIn))
    }
}

@Test(arguments: [
    "", "standin", "./standin", "~/standin", "~", " /standin",
    "/standin\n", "/stand\u{0}in", "/stand\tin", "/stand\u{7F}in",
])
func `a stand-in that is not an absolute path or holds a control character is refused`(raw: String) {
    #expect(ProfileStandIn.folder(from: raw, home: "/Volumes/Acme/home") == nil)
}

@Test func `a stand-in longer than PATH_MAX is refused, and one at the limit is not`() {
    let atLimit = "/" + String(repeating: "a", count: ProfileStandIn.maximumLength - 1)
    let tooLong = atLimit + "a"

    #expect(ProfileStandIn.maximumLength == Int(PATH_MAX))
    #expect(ProfileStandIn.folder(from: tooLong, home: "/Volumes/Acme/home") == nil)
    #expect(ProfileStandIn.folder(from: atLimit, home: "/Volumes/Acme/home") != nil)
}
