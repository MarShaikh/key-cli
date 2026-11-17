import XCTest
import KeyCore

final class SSHTargetTests: XCTestCase {
    func testParsesUserAndHost() {
        XCTAssertEqual(SSHTarget(parsing: "mshaikh@bia.cmd.ox.ac.uk"), SSHTarget(user: "mshaikh", host: "bia.cmd.ox.ac.uk"))
        XCTAssertEqual(SSHTarget(parsing: "example.org"), SSHTarget(user: nil, host: "example.org"))
        XCTAssertEqual(SSHTarget(parsing: "10.0.0.5"), SSHTarget(user: nil, host: "10.0.0.5"))
    }

    // Anything else could break out of the Host block it is written into.
    func testRefusesCharactersThatAreUnsafeInConfig() {
        XCTAssertNil(SSHTarget(parsing: ""))
        XCTAssertNil(SSHTarget(parsing: "me@"))
        XCTAssertNil(SSHTarget(parsing: "@host"))
        XCTAssertNil(SSHTarget(parsing: "a@b@c"))
        XCTAssertNil(SSHTarget(parsing: "host name"))
        XCTAssertNil(SSHTarget(parsing: "host\nProxyCommand evil"))
        XCTAssertNil(SSHTarget(parsing: "*.example.org"))
        XCTAssertNil(SSHTarget(parsing: "-oProxyCommand=evil"))
    }
}

final class ConfigIncludeTests: XCTestCase {
    let include = "Include config.d/key-cli"

    func testGoesAfterLeadingIncludesAndBeforeTheFirstHost() {
        let config = """
            # Added by OrbStack
            Include ~/.orbstack/ssh/config

            Host bia.cmd.ox.ac.uk
              User mshaikh

            """
        XCTAssertEqual(ConfigInclude.adding(include, to: config), """
            # Added by OrbStack
            Include ~/.orbstack/ssh/config

            Include config.d/key-cli
            Host bia.cmd.ox.ac.uk
              User mshaikh

            """)
    }

    func testFirstMatchBlockAlsoCounts() {
        XCTAssertEqual(ConfigInclude.adding(include, to: "Match host foo\n  User x\n"),
                       "Include config.d/key-cli\nMatch host foo\n  User x\n")
    }

    func testHostKeywordIsCaseInsensitiveAndMayBeIndented() {
        XCTAssertEqual(ConfigInclude.adding(include, to: "  host foo\n"),
                       "Include config.d/key-cli\n  host foo\n")
    }

    func testEmptyOrHostlessConfigGetsItAtTheEnd() {
        XCTAssertEqual(ConfigInclude.adding(include, to: ""), "Include config.d/key-cli\n")
        XCTAssertEqual(ConfigInclude.adding(include, to: "ServerAliveInterval 30"),
                       "ServerAliveInterval 30\nInclude config.d/key-cli\n")
    }

    func testAlreadyIncludedReturnsNil() {
        XCTAssertNil(ConfigInclude.adding(include, to: "Include config.d/key-cli\nHost x\n"))
    }
}

final class ManagedHostsTests: XCTestCase {
    let bia = ManagedHosts.Entry(
        target: SSHTarget(user: "mshaikh", host: "bia.cmd.ox.ac.uk"),
        port: nil, identityFile: "~/.ssh/id_ecdsa_sk_rk_default")
    let lab = ManagedHosts.Entry(
        target: SSHTarget(user: nil, host: "lab.example.org"),
        port: 2222, identityFile: "~/.ssh/id_ecdsa_sk_rk_work")

    func testRendersAHostBlock() {
        XCTAssertEqual(ManagedHosts.setting(bia, in: ""), """
            # Written by `key ssh add`. Edit with care: the tool rewrites these blocks.

            Host bia.cmd.ox.ac.uk
              HostName bia.cmd.ox.ac.uk
              User mshaikh
              IdentityFile ~/.ssh/id_ecdsa_sk_rk_default
              IdentitiesOnly yes
              SecurityKeyProvider /usr/lib/ssh-keychain.dylib

            """)
    }

    func testAddsPortAndLeavesOutAMissingUser() {
        XCTAssertEqual(ManagedHosts.setting(lab, in: ""), """
            # Written by `key ssh add`. Edit with care: the tool rewrites these blocks.

            Host lab.example.org
              HostName lab.example.org
              Port 2222
              IdentityFile ~/.ssh/id_ecdsa_sk_rk_work
              IdentitiesOnly yes
              SecurityKeyProvider /usr/lib/ssh-keychain.dylib

            """)
    }

    func testReplacesTheBlockForTheSameHostAndKeepsOthers() {
        let both = ManagedHosts.setting(lab, in: ManagedHosts.setting(bia, in: ""))
        XCTAssertEqual(ManagedHosts.hosts(in: both), ["bia.cmd.ox.ac.uk", "lab.example.org"])

        let moved = ManagedHosts.Entry(target: bia.target, port: 2200, identityFile: bia.identityFile)
        let updated = ManagedHosts.setting(moved, in: both)
        XCTAssertEqual(ManagedHosts.hosts(in: updated), ["bia.cmd.ox.ac.uk", "lab.example.org"])
        XCTAssertTrue(updated.contains("Port 2200"))
        XCTAssertEqual(updated.components(separatedBy: "Host bia.cmd.ox.ac.uk").count, 2)
    }
}
