// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/CertificateNFT.sol";
import "contracts/Airworthiness.sol";
import "contracts/CertificateTypes.sol";

// Mock contract to simulate Airworthiness contract behavior
contract MockAirworthiness {
    address public regulatoryAuthority;
    mapping(uint256 => bool) public certifiedApplications;

    constructor(address _regulatoryAuthority) {
        regulatoryAuthority = _regulatoryAuthority;
    }

    function isCertified(uint256 applicationId) external view returns (bool) {
        return certifiedApplications[applicationId];
    }

    function certifyApplication(uint256 applicationId) external {
        require(msg.sender == regulatoryAuthority, "Only regulatory authority allowed");
        certifiedApplications[applicationId] = true;
    }
}

contract CertificateNFTTest is Test {
    CertificateNFT certificateNFT;
    MockAirworthiness mockAirworthiness;

    address admin = address(1);
    address authority = address(2);
    address unauthorizedUser = address(3);
    address issuer = address(4);

    uint256 testApplicationId = 1;
    string testMetadataURI = "ipfs://certificate-metadata";
    function setUp() public {
        // Deploy the CertificateNFT contract
        certificateNFT = new CertificateNFT();
        mockAirworthiness = new MockAirworthiness(authority);

        // Since the deployer is already the admin, we can directly add an authority
        vm.prank(address(this)); // Foundry tests run as address(this) by default
        certificateNFT.addAuthority(authority);
    }


    function test_ShouldAllowAuthorityToMintCertificate() public {
        // Certify the Airworthiness application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        // Verify the certificate exists
        uint256 tokenId = 1; // First certificate should have ID 1
        assertEq(certificateNFT.ownerOf(tokenId), authority);
        assertEq(certificateNFT.getIssuer(tokenId), issuer);
        assertEq(uint256(certificateNFT.getCertificateType(tokenId)), uint256(CertificateTypes.CertificateType.Airworthiness));
        assertTrue(certificateNFT.isValid(tokenId));
    }

    function test_ShouldFailToMintCertificateIfApplicationNotCertified() public {
        // Try to mint without certifying the Airworthiness application
        vm.prank(authority);
        vm.expectRevert("Application ID does not exist in the linked contract");
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );
    }

    function test_ShouldFailIfNonAuthorityTriesToMint() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Caller is not an authority");
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );
    }

    function test_ShouldRetrieveCertificateType() public {
        // Certify the application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Export,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        uint256 tokenId = 1;
        assertEq(uint256(certificateNFT.getCertificateType(tokenId)), uint256(CertificateTypes.CertificateType.Export));
    }

    function test_ShouldRetrieveIssuer() public {
        // Certify the application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Import,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        uint256 tokenId = 1;
        assertEq(certificateNFT.getIssuer(tokenId), issuer);
    }

    function test_ShouldCheckCertificateValidity() public {
        // Certify the application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        uint256 tokenId = 1;
        assertTrue(certificateNFT.isValid(tokenId));
    }

    function test_ShouldAllowIssuerToRevokeCertificate() public {
        // Certify the application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        uint256 tokenId = 1;

        // Revoke the certificate
        vm.prank(issuer);
        certificateNFT.revokeCertificate(tokenId);

        // Ensure it's now invalid
        assertFalse(certificateNFT.isValid(tokenId));
    }

    function test_ShouldFailIfNonIssuerTriesToRevoke() public {
        // Certify the application
        vm.prank(authority);
        mockAirworthiness.certifyApplication(testApplicationId);

        // Mint the certificate
        vm.prank(authority);
        certificateNFT.mintCertificate(
            testMetadataURI,
            CertificateTypes.CertificateType.Airworthiness,
            issuer,
            address(mockAirworthiness),
            testApplicationId
        );

        uint256 tokenId = 1;

        // Attempt to revoke as an unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the issuer can revoke this certificate");
        certificateNFT.revokeCertificate(tokenId);
    }
}
