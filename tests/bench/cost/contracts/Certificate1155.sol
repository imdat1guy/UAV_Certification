// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./CertificateTypes.sol";

contract Certificate1155 is ERC1155, AccessControl {
    using CertificateTypes for CertificateTypes.CertificateType;

    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    struct CertificateData {
        CertificateTypes.CertificateType ctype;
        address issuer;
        bool isValid;
        address linkedContract;      // optional: for symmetry with ERC-721
        uint256 linkedApplicationId; // optional
        bytes32 profileId;
        bytes32 controlsHash;
    }

    uint256 public nextId;
    mapping(uint256 => CertificateData) public certData;

    event CertificateBatchMinted(
        uint256[] ids,
        CertificateTypes.CertificateType indexed ctype,
        address indexed issuer,
        bytes32 profileId,
        bytes32 controlsHash
    );

    constructor() ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyAuthority() {
        require(hasRole(AUTHORITY_ROLE, msg.sender), "Caller is not an authority");
        _;
    }

    function addAuthority(address authority) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _grantRole(AUTHORITY_ROLE, authority);
    }

    // Batch mint N certificates (amount = 1 each), recording per-id metadata
    function mintBatchCertificates(
        uint256 n,
        CertificateTypes.CertificateType ctype,
        address issuer,
        bytes32 profileId,
        bytes32 controlsHash
    ) external onlyAuthority returns (uint256[] memory ids) {
        require(n > 0, "n = 0");
        ids = new uint256[](n);
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 id = nextId++;
            ids[i] = id;
            amounts[i] = 1;
            certData[id] = CertificateData({
                ctype: ctype,
                issuer: issuer,
                isValid: true,
                linkedContract: address(0),
                linkedApplicationId: 0,
                profileId: profileId,
                controlsHash: controlsHash
            });
        }
        _mintBatch(msg.sender, ids, amounts, "");
        emit CertificateBatchMinted(ids, ctype, issuer, profileId, controlsHash);
        return ids;
    }

    function getCertificateType(uint256 id) external view returns (CertificateTypes.CertificateType) {
        require(certExists(id), "Certificate does not exist");
        return certData[id].ctype;
    }

    function getProfileId(uint256 id) external view returns (bytes32) {
        require(certExists(id), "Certificate does not exist");
        return certData[id].profileId;
    }

    function isValid(uint256 id) external view returns (bool) {
        require(certExists(id), "Certificate does not exist");
        return certData[id].isValid;
    }

    function revokeCertificate(uint256 id) external {
        require(certExists(id), "Certificate does not exist");
        CertificateData storage d = certData[id];
        require(msg.sender == d.issuer, "Only issuer can revoke");
        d.isValid = false;
    }

    function certExists(uint256 id) internal view returns (bool) {
        // ERC1155 has no ownerOf; existence = data initialized & balance > 0
        //return dOwnerBalance(id) > 0;
        return certData[id].issuer != address(0);
    }

    function dOwnerBalance(uint256 id) internal view returns (uint256) {
        // Authority holds the tokens until linked
        // Any authority can hold; check balance of caller is not robust for existence.
        // Use a cheap existence heuristic: isValid was initialized or issuer != 0
        // plus totalSupply if you later add ERC1155Supply. For now, rely on isValid default false.
        return balanceOf(msg.sender, id);
    }
}
