// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {UAVPassportNFT} from "contracts/UAVPassportNFT.sol";
import {CertificateTypes} from "contracts/CertificateTypes.sol";
import {Airworthiness} from "contracts/Airworthiness.sol";

// Minimal certificate mock used by fuzzing
contract CertMock {
    mapping(uint256 => address) public owners;
    mapping(uint256 => CertificateTypes.CertificateType) public certTypes;

    function setOwner(uint256 tokenId, address owner) external { owners[tokenId] = owner; }
    function ownerOf(uint256 tokenId) external view returns (address) { return owners[tokenId]; }

    function setCertificateType(uint256 tokenId, CertificateTypes.CertificateType c) external { certTypes[tokenId] = c; }
    function getCertificateType(uint256 tokenId) external view returns (CertificateTypes.CertificateType) { return certTypes[tokenId]; }

    // Simple safeTransfer; no reentrancy here—used for fuzz setup
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(owners[tokenId] == from, "not owner");
        owners[tokenId] = to;
    }
}

// Mock UAV NFT interface used by Airworthiness
contract MockUAVPassportNFT {
    mapping(uint256 => address) public owners;
    function setOwner(uint256 tokenId, address owner) external { owners[tokenId] = owner; }
    function ownerOf(uint256 tokenId) external view returns (address) { return owners[tokenId]; }
}

contract Fuzz_UAVPassport_and_Airworthiness is Test {
    UAVPassportNFT passport;
    CertMock cert;
    Airworthiness air;
    MockUAVPassportNFT mockUAV;

    address admin = address(1);
    address manufacturer = address(2);
    address authority = address(3);

    function setUp() public {
        passport = new UAVPassportNFT();
        cert = new CertMock();

        // Roles
        vm.prank(address(this));
        passport.grantRole(passport.DEFAULT_ADMIN_ROLE(), admin);

        vm.prank(admin);
        passport.addManufacturer(manufacturer);

        vm.prank(admin);
        passport.addAuthority(authority);

        // Airworthiness uses its own RA address
        air = new Airworthiness(authority);

        // Mock UAV owner registry for Airworthiness
        mockUAV = new MockUAVPassportNFT();
    }

    /// Fuzz: non-authority can never link a certificate
    function testFuzz_NonAuthorityCannotLinkCertificate(address attacker) public {
        vm.assume(attacker != address(0) && attacker != authority && attacker != manufacturer);

        // Mint a UAV
        vm.prank(manufacturer);
        passport.mintUAV("SN-1", address(0), 0, "ipfs://meta");

        // Give authority ownership of a certificate
        cert.setOwner(1, authority);
        cert.setCertificateType(1, CertificateTypes.CertificateType.Airworthiness);

        // Unauthorized caller tries to link
        vm.prank(attacker);
        vm.expectRevert("Caller is not an authority");
        passport.linkCertificate(1, address(cert), 1);
    }

    /// Fuzz: only UAV owner can submit airworthiness application
    function testFuzz_OnlyOwnerCanSubmitAirworthiness(address owner, address notOwner) public {
        vm.assume(owner != address(0) && notOwner != address(0) && owner != notOwner);

        // UAV #7 is owned by `owner`
        mockUAV.setOwner(7, owner);

        // notOwner cannot submit
        vm.prank(notOwner);
        vm.expectRevert("Caller does not own the specified UAVPassportNFT");
        air.submitApplication(address(mockUAV), 7, "ipfs://docs");

        // owner can submit
        vm.prank(owner);
        air.submitApplication(address(mockUAV), 7, "ipfs://docs");
    }

    /// Fuzz: UAV mint values (serial and cid) do not break invariants and remain retrievable
    function testFuzz_MintUAV_MetadataRoundTrip(string memory serial, string memory cid) public {
        // Keep inputs reasonable in size
        vm.assume(bytes(serial).length > 0 && bytes(serial).length < 128);
        vm.assume(bytes(cid).length > 0 && bytes(cid).length < 256);

        vm.prank(manufacturer);
        passport.mintUAV(serial, address(0), 0, cid);

        UAVPassportNFT.UAVData memory d = passport.getUAVData(passport.tokenCounter());
        assertEq(d.tokenId, passport.tokenCounter());
        assertEq(d.owner, manufacturer);
        assertEq(keccak256(bytes(d.serialNumber)), keccak256(bytes(serial)));
        assertEq(keccak256(bytes(d.ipfsMetadataCID)), keccak256(bytes(cid)));
    }
}
