import DontBurnCore
import Testing

private let everyStatus: [LoginItemStatus] = [.notRegistered, .enabled, .requiresApproval, .notFound]

@Test(arguments: everyStatus, [nil, "The operation couldn't be completed."] as [String?])
func `the switch is on only while the app starts at login, refused or not`(status: LoginItemStatus, refusal: String?) {
    #expect(LoginItemSwitch(status: status, refusal: refusal).isOn == (status == .enabled))
}

@Test(arguments: [.notRegistered, .enabled, .notFound] as [LoginItemStatus])
func `without a refusal or System Settings in the way there is no note`(status: LoginItemStatus) {
    #expect(LoginItemSwitch(status: status).note == nil)
    #expect(LoginItemSwitch(status: status, refusal: nil).note == nil)
}

@Test(arguments: [.notRegistered, .enabled, .notFound] as [LoginItemStatus])
func `a refused change shows the system's reason under the switch`(status: LoginItemStatus) {
    let shown = LoginItemSwitch(status: status, refusal: "Operation not permitted")
    #expect(shown.note == .refused(reason: "Operation not permitted"))
}

@Test(arguments: [nil, "Operation not permitted"] as [String?])
func `switched off in System Settings the note says so, even after a refusal`(refusal: String?) {
    #expect(LoginItemSwitch(status: .requiresApproval, refusal: refusal).note == .offInSystemSettings)
}

@Test(arguments: [
    ("system", .system),
    ("stand-in", .standIn),
    ("refuse", .refuse),
    ("approval", .approval),
] as [(String, LoginItemCheck)])
func `the login item check is named by its launch argument`(raw: String, check: LoginItemCheck) {
    #expect(LoginItemCheck(launchArgument: raw) == check)
}

@Test func `without the launch argument there is no login item check`() {
    #expect(LoginItemCheck(launchArgument: nil) == nil)
}

@Test(arguments: [
    "", "bogus", "yes", "YES", "1",
    "System", "SYSTEM", "Stand-In", "STAND-IN", "Refuse", "Approval",
    "standIn", "stand_in", "standin", "stand in",
    " system", "system ", "system\n", "\tsystem", "stand-in\u{0}",
    "syst\u{E9}m", "s\u{0443}stem",
    "approvals", "refused", "system-",
])
func `the login item check rejects anything but its exact names`(raw: String) {
    #expect(LoginItemCheck(launchArgument: raw) == nil)
}

@Test(arguments: [
    String(repeating: "a", count: 17),
    "system" + String(repeating: " ", count: 11),
    "approval" + String(repeating: " ", count: 9),
    String(repeating: "\u{E9}", count: 9),
    String(repeating: "system", count: 200),
])
func `a login item argument over 16 bytes is ignored`(raw: String) {
    #expect(raw.utf8.count > 16)
    #expect(LoginItemCheck(launchArgument: raw) == nil)
}
