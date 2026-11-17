import XCTest
import KeyCore

// The bia-ssh rows are captured from `sc_auth list-ctk-identities` (with and without
// `-t ssh`) on macOS 27.2.1. The default rows are made up in the same layout.
let sha1Listing = """
    Key Type Public Key Hash                          Prot Label   Common Name Email Address Valid To          Valid
    p-256-ne 460DF44A7A8CD625CB9FE1564D4F78D3FB4CCCDF bio  bia-ssh bia-ssh                   16/09/2027, 11:59 YES
    p-256-ne 0123456789ABCDEF0123456789ABCDEF01234567 bio  default                           17/11/2027, 15:00 YES
    """

let sshListing = """
    Key Type Public Key Hash                                    Prot Label   Common Name Email Address Valid To          Valid
    p-256-ne SHA256:WJ45e/GGwzzUYyA3bLOXAJUiUJnu536YGB0PuHiUXmY bio  bia-ssh bia-ssh                   16/09/2027, 11:59 YES
    p-256-ne SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ bio  default                           17/11/2027, 15:00 YES
    """

final class IdentityListingTests: XCTestCase {
    func testJoinsHashesAndFingerprintsByLabel() {
        XCTAssertEqual(IdentityListing.identities(sha1: sha1Listing, ssh: sshListing), [
            SecureEnclaveIdentity(
                label: "bia-ssh",
                hash: "460DF44A7A8CD625CB9FE1564D4F78D3FB4CCCDF",
                fingerprint: "SHA256:WJ45e/GGwzzUYyA3bLOXAJUiUJnu536YGB0PuHiUXmY"),
            SecureEnclaveIdentity(
                label: "default",
                hash: "0123456789ABCDEF0123456789ABCDEF01234567",
                fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"),
        ])
    }

    func testEmptyListingHasNoIdentities() {
        let header = "Key Type Public Key Hash Prot Label Common Name Email Address Valid To Valid\n"
        XCTAssertEqual(IdentityListing.identities(sha1: header, ssh: header), [])
    }

    func testRefusesListingsThatDisagree() {
        let oneRow = sha1Listing.split(separator: "\n").prefix(2).joined(separator: "\n")
        XCTAssertNil(IdentityListing.identities(sha1: oneRow, ssh: sshListing))
    }

    func testLabelRules() {
        XCTAssertTrue(IdentityListing.isValidLabel("bia-ssh"))
        XCTAssertTrue(IdentityListing.isValidLabel("work_2.mac"))
        XCTAssertFalse(IdentityListing.isValidLabel(""))
        XCTAssertFalse(IdentityListing.isValidLabel("two words"))
        XCTAssertFalse(IdentityListing.isValidLabel("../escape"))
        XCTAssertFalse(IdentityListing.isValidLabel("café"))
    }

    func testFingerprintFromKeygenLine() {
        XCTAssertEqual(
            fingerprint(fromKeygenLine: "256 SHA256:WJ45e/GGwzzUYyA3bLOXAJUiUJnu536YGB0PuHiUXmY ssh: (ECDSA-SK)"),
            "SHA256:WJ45e/GGwzzUYyA3bLOXAJUiUJnu536YGB0PuHiUXmY")
        XCTAssertNil(fingerprint(fromKeygenLine: "not a key"))
    }
}
