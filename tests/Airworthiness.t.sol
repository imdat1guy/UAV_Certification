// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/Airworthiness.sol";

// Mock UAVPassportNFT contract to simulate ownership verification
contract MockUAVPassportNFT {
    mapping(uint256 => address) public owners;

    function setOwner(uint256 tokenId, address owner) external {
        owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }
}

contract AirworthinessTest is Test {
    Airworthiness airworthiness;
    MockUAVPassportNFT mockUAVNFT;

    address owner = address(1);
    address regulatoryAuthority = address(2);
    address unauthorizedUser = address(3);
    uint256 testTokenId = 1;

    function setUp() public {
        airworthiness = new Airworthiness(regulatoryAuthority);
        mockUAVNFT = new MockUAVPassportNFT();
        mockUAVNFT.setOwner(testTokenId, owner);
    }

    function test_ShouldAllowUAVOwnerToSubmitApplication() public {
        vm.label(address(this), "Should allow the UAV owner to submit an application");

        vm.startPrank(owner);
        airworthiness.submitApplication(address(mockUAVNFT), testTokenId, "ipfs://test-docs");
        vm.stopPrank();

        (uint256 id, , uint256 uavTokenId, string memory ipfsHash, Airworthiness.CertificationStatus status) = airworthiness.applications(1);

        assertEq(id, 1);
        assertEq(uavTokenId, testTokenId);
        assertEq(uint256(status), uint256(Airworthiness.CertificationStatus.Pending));
        assertEq(keccak256(bytes(ipfsHash)), keccak256(bytes("ipfs://test-docs")));
    }

    function test_ShouldAllowOnlyRegulatoryToCompleteInspection() public {
        vm.label(address(this), "Should allow only the regulatory authority to complete an inspection");

        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Only regulatory authority allowed");
        airworthiness.completeInspection(1, "ipfs://inspection-report");
        vm.stopPrank();

        vm.startPrank(regulatoryAuthority);
        airworthiness.completeInspection(1, "ipfs://inspection-report");
        vm.stopPrank();
    }

    function test_ShouldAllowOnlyRegulatoryToIssueCertificate() public {
        vm.label(address(this), "Should allow only the regulator to issue an airworthiness certificate");

        vm.startPrank(owner);
        airworthiness.submitApplication(address(mockUAVNFT), testTokenId, "ipfs://test-docs");
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("Only regulatory authority allowed");
        airworthiness.issueCertificate(1, "ipfs://certificate");
        vm.stopPrank();

        vm.startPrank(regulatoryAuthority);
        airworthiness.issueCertificate(1, "ipfs://certificate");
        vm.stopPrank();

        (, , , , Airworthiness.CertificationStatus status) = airworthiness.applications(1);
        assertEq(uint256(status), uint256(Airworthiness.CertificationStatus.Certified));
    }

    function test_ShouldNotAllowIssuingCertificateBeforeApplication() public {
        vm.label(address(this), "Should not allow issuing a certificate before submitting an application");

        vm.startPrank(regulatoryAuthority);
        vm.expectRevert("Application does not exist");
        airworthiness.issueCertificate(99, "ipfs://certificate");
        vm.stopPrank();
    }

    function test_ShouldCorrectlyRetrieveCertificationStatus() public {
        vm.label(address(this), "Should correctly retrieve certification status");

        vm.startPrank(owner);
        airworthiness.submitApplication(address(mockUAVNFT), testTokenId, "ipfs://test-docs");
        vm.stopPrank();

        bool certifiedBefore = airworthiness.isCertified(1);
        assertEq(certifiedBefore, false);

        vm.startPrank(regulatoryAuthority);
        airworthiness.issueCertificate(1, "ipfs://certificate");
        vm.stopPrank();

        bool certifiedAfter = airworthiness.isCertified(1);
        assertEq(certifiedAfter, true);
    }

    function test_ShouldReturnFalseForNonExistentApplications() public {
        vm.label(address(this), "Should return false for non-existent applications in isCertified");

        bool certified = airworthiness.isCertified(999); // Non-existent application ID
        assertEq(certified, false);
    }
}
