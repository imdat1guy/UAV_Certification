// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {UAVPassportNFT} from "contracts/UAVPassportNFT.sol";
import {CertificateTypes} from "contracts/CertificateTypes.sol";

contract MaliciousCert {
    mapping(uint256 => address) public owners;
    mapping(uint256 => CertificateTypes.CertificateType) public certTypes;

    address public passportAddr;
    bool public reenterEnabled;
    uint256 public reenterToUAV;

    function setPassport(address p) external { passportAddr = p; }
    function setOwner(uint256 tokenId, address owner) external { owners[tokenId] = owner; }
    function ownerOf(uint256 tokenId) external view returns (address) { return owners[tokenId]; }
    function setCertificateType(uint256 tokenId, CertificateTypes.CertificateType c) external { certTypes[tokenId] = c; }
    function getCertificateType(uint256 tokenId) external view returns (CertificateTypes.CertificateType) { return certTypes[tokenId]; }

    function enableReenter(uint256 uavId) external { reenterEnabled = true; reenterToUAV = uavId; }

    // Attempt a reentrant call to link the same certificate to a different UAV
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        if (reenterEnabled && to == passportAddr) {
            // Try to reenter BEFORE we update owner mapping (worst-case ordering)
            try UAVPassportNFT(to).linkCertificate(reenterToUAV, address(this), tokenId) {
                // ignore
            } catch {}
        }
        owners[tokenId] = to;
    }
}

contract Attack_Reentrancy_OnLink is Test {
    UAVPassportNFT passport;
    MaliciousCert cert;

    address admin = address(1);
    address manufacturer = address(2);
    address authority = address(3);

    function setUp() public {
        passport = new UAVPassportNFT();
        cert = new MaliciousCert();
        cert.setPassport(address(passport));

        // roles
        vm.prank(address(this));
        passport.grantRole(passport.DEFAULT_ADMIN_ROLE(), admin);

        vm.prank(admin);
        passport.addManufacturer(manufacturer);

        // IMPORTANT: grant authority to BOTH the EOA and the malicious contract
        // to simulate worst-case reentry with privileges
        vm.prank(admin);
        passport.addAuthority(authority);
        vm.prank(admin);
        passport.addAuthority(address(cert));

        // two UAVs to try to double-link
        vm.prank(manufacturer);
        passport.mintUAV("U1", address(0), 0, "ipfs://u1");
        vm.prank(manufacturer);
        passport.mintUAV("U2", address(0), 0, "ipfs://u2");

        // authority initially owns cert #1
        cert.setOwner(1, authority);
        cert.setCertificateType(1, CertificateTypes.CertificateType.Airworthiness);
    }

    function test_ReentrancyAttemptCannotBypassOwnershipChecks() public {
        // Enable reentry aimed at linking to UAV #2 during transfer to passport
        cert.enableReenter(2);

        // First link (authority initiates)
        vm.prank(authority);
        passport.linkCertificate(1, address(cert), 1);

        // Post-conditions: certificate belongs to passport, not the attacker,
        // and there is only one link recorded for UAV #1.
        assertEq(cert.ownerOf(1), address(passport));

        UAVPassportNFT.LinkedCertificate[] memory c1 = passport.getLinkedCertificates(1);
        assertEq(c1.length, 1);

        UAVPassportNFT.LinkedCertificate[] memory c2 = passport.getLinkedCertificates(2);
        assertEq(c2.length, 0); // reentrant link to UAV #2 must NOT exist
    }
}
