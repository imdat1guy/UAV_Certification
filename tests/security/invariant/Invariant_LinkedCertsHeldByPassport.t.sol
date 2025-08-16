// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
//import "forge-std/StdInvariant.sol";
import {UAVPassportNFT} from "contracts/UAVPassportNFT.sol";
import {CertificateTypes} from "contracts/CertificateTypes.sol";

// Lightweight handler: mints a UAV and links a fresh certificate each time
contract Handler is Test {
    UAVPassportNFT public passport;
    address public manufacturer;
    address public authority;

    // Simple cert mock living here to keep state centralized
    mapping(uint256 => address) public owners;
    uint256 public nextCertId;
    mapping(uint256 => uint256) public certLinkedTo; // cert -> uav

    constructor(UAVPassportNFT _passport, address _manufacturer, address _authority) {
        passport = _passport;
        manufacturer = _manufacturer;
        authority = _authority;
    }

    function ownerOf(uint256 tokenId) external view returns (address) { return owners[tokenId]; }
    function getCertificateType(uint256) external pure returns (CertificateTypes.CertificateType) {
        return CertificateTypes.CertificateType.Airworthiness;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(owners[tokenId] == from, "not owner");
        owners[tokenId] = to;
    }

    function mintAndLink() external {
        // mint a UAV
        vm.prank(manufacturer);
        passport.mintUAV("H", address(0), 0, "ipfs://h");

        uint256 uavId = passport.tokenCounter();

        // create a cert id "owned" by authority
        nextCertId++;
        owners[nextCertId] = authority;

        // link it
        vm.prank(authority);
        passport.linkCertificate(uavId, address(this), nextCertId);

        certLinkedTo[nextCertId] = uavId;
    }
}

contract Invariant_LinkedCertsHeldByPassport is Test {
    UAVPassportNFT passport;
    Handler handler;

    address admin = address(1);
    address manufacturer = address(2);
    address authority = address(3);

    function setUp() public {
        passport = new UAVPassportNFT();

        vm.prank(address(this));
        passport.grantRole(passport.DEFAULT_ADMIN_ROLE(), admin);
        vm.prank(admin);
        passport.addManufacturer(manufacturer);
        vm.prank(admin);
        passport.addAuthority(authority);

        handler = new Handler(passport, manufacturer, authority);
        targetContract(address(handler)); // Foundry will fuzz-call mintAndLink()
    }

    // Invariant: every linked certificate is held by the passport
    function invariant_CertsHeldByPassport() public {
        // Loop through cert ids that were linked
        for (uint256 i = 1; i <= handler.nextCertId(); i++) {
            uint256 uavId = handler.certLinkedTo(i);
            if (uavId == 0) continue; // not linked

            // owner of cert i must be the passport
            assertEq(handler.ownerOf(i), address(passport), "linked cert not held by passport");
        }
    }
}
