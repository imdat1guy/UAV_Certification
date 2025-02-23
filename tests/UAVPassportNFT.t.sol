// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/UAVPassportNFT.sol";
import "contracts/CertificateNFT.sol";
import "contracts/TypeCertificate.sol";

contract MockCertificateNFT {
    mapping(uint256 => address) public owners;
    mapping(uint256 => CertificateTypes.CertificateType) public certTypes;

    function setOwner(uint256 tokenId, address owner) external {
        owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function setCertificateType(uint256 tokenId, CertificateTypes.CertificateType certType) external {
        certTypes[tokenId] = certType;
    }

    function getCertificateType(uint256 tokenId) external view returns (CertificateTypes.CertificateType) {
        return certTypes[tokenId];
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(owners[tokenId] == from, "Not owner");
        owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
}








contract UAVPassportNFTTest is Test {
    UAVPassportNFT uavPassportNFT;
    MockCertificateNFT mockCertificateNFT;

    address admin = address(1);
    address manufacturer = address(2);
    address regulatoryAuthority = address(3);
    address newOwner = address(4);
    address unauthorizedUser = address(5);

    string testSerialNumber = "UAV-123";
    string testMetadataCID = "ipfs://metadata";
    uint256 testUAVTokenId = 1;
    uint256 testCertificateTokenId = 1;

    function setUp() public {
    uavPassportNFT = new UAVPassportNFT();
    mockCertificateNFT = new MockCertificateNFT();

    vm.prank(address(this));
    uavPassportNFT.grantRole(uavPassportNFT.DEFAULT_ADMIN_ROLE(), admin);

    vm.prank(admin);
    uavPassportNFT.addManufacturer(manufacturer);

    vm.prank(admin);
    uavPassportNFT.addAuthority(regulatoryAuthority);

    assertTrue(uavPassportNFT.hasRole(uavPassportNFT.AUTHORITY_ROLE(), regulatoryAuthority), "Regulatory authority missing AUTHORITY_ROLE");
}


    function test_ShouldAllowManufacturerToMintUAV() public {
        vm.prank(manufacturer);
        uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

        UAVPassportNFT.UAVData memory uav = uavPassportNFT.getUAVData(testUAVTokenId);

        assertEq(uav.tokenId, testUAVTokenId);
        assertEq(uav.serialNumber, testSerialNumber);
        assertEq(uav.owner, manufacturer);
        assertEq(keccak256(bytes(uav.ipfsMetadataCID)), keccak256(bytes(testMetadataCID)));
    }

    function test_ShouldAllowAuthorityToLinkCertificate() public {

    vm.prank(manufacturer);
    uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

    assertEq(uavPassportNFT.ownerOf(testUAVTokenId), manufacturer, "UAV owner is incorrect");

    assertTrue(uavPassportNFT.hasRole(uavPassportNFT.AUTHORITY_ROLE(), regulatoryAuthority), "Regulatory authority missing AUTHORITY_ROLE");

    vm.prank(regulatoryAuthority);
    mockCertificateNFT.setOwner(testCertificateTokenId, regulatoryAuthority);
    mockCertificateNFT.setCertificateType(testCertificateTokenId, CertificateTypes.CertificateType.Airworthiness);

    address certOwnerBefore = mockCertificateNFT.ownerOf(testCertificateTokenId);
    assertEq(certOwnerBefore, regulatoryAuthority, "Mock contract is not returning the expected owner");

    //vm.prank(regulatoryAuthority);
    //mockCertificateNFT.safeTransferFrom(regulatoryAuthority, address(uavPassportNFT), testCertificateTokenId);



    vm.prank(regulatoryAuthority);
    uavPassportNFT.linkCertificate(testUAVTokenId, address(mockCertificateNFT), testCertificateTokenId);

    address certOwnerAfter = mockCertificateNFT.ownerOf(testCertificateTokenId);
    assertEq(certOwnerAfter, address(uavPassportNFT), "UAVPassportNFT contract did not receive ownership of the certificate");

    UAVPassportNFT.LinkedCertificate[] memory linkedCerts = uavPassportNFT.getLinkedCertificates(testUAVTokenId);
    assertEq(linkedCerts[0].certificateContract, address(mockCertificateNFT), "Certificate contract mismatch");
    assertEq(linkedCerts[0].certificateTokenId, testCertificateTokenId, "Certificate token ID mismatch");
}




    function test_ShouldFailIfNonAuthorityTriesToLinkCertificate() public {
        vm.prank(manufacturer);
        uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

        vm.prank(unauthorizedUser);
        vm.expectRevert("Caller is not an authority");
        uavPassportNFT.linkCertificate(testUAVTokenId, address(mockCertificateNFT), testCertificateTokenId);
    }

    function test_ShouldAllowOwnerToTransferUAV() public {
        vm.prank(manufacturer);
        uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

        vm.prank(manufacturer);
        uavPassportNFT.transferUAV(newOwner, testUAVTokenId);

        UAVPassportNFT.UAVData memory uav = uavPassportNFT.getUAVData(testUAVTokenId);
        assertEq(uav.owner, newOwner);
    }

    function test_ShouldAllowAuthorityToRecordImportExport() public {
        vm.prank(manufacturer);
        uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

        string memory countryCode = "US";

        vm.prank(regulatoryAuthority);
        uavPassportNFT.recordImportExport(testUAVTokenId, countryCode);

        string[] memory trace = uavPassportNFT.getImportExportTrace(testUAVTokenId);
        assertEq(keccak256(bytes(trace[0])), keccak256(bytes(countryCode)));
    }

    function test_ShouldFailIfNonAuthorityTriesToRecordImportExport() public {
        vm.prank(manufacturer);
        uavPassportNFT.mintUAV(testSerialNumber, address(0), 0, testMetadataCID);

        vm.prank(unauthorizedUser);
        vm.expectRevert("Caller is not an authority");
        uavPassportNFT.recordImportExport(testUAVTokenId, "FR");
    }
}

