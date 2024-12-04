// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import statements
import "../.deps/npm/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../.deps/npm/@openzeppelin/contracts/access/AccessControl.sol";
import "../.deps/npm/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./CertificateTypes.sol";

interface CertificateNFTInterface {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getCertificateType(uint256 tokenId) external view returns (CertificateTypes.CertificateType);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract UAVPassportNFT is ERC721, AccessControl, IERC721Receiver {
    using Strings for uint256;
    using CertificateTypes for CertificateTypes.CertificateType;

    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    uint256 public tokenCounter;

    struct LinkedCertificate{
        address certificateContract;
        uint256 certificateTokenId;
        CertificateTypes.CertificateType ctype;
    }

    // Struct to store UAV metadata
    struct UAVData {
        uint256 tokenId;
        string serialNumber; // Unique serial number or Remote ID
        address typeCertificateContract; 
        uint256 typeCertificateApplicationId; //the type certificate under which this UAV was manufactured
        string ipfsMetadataCID; // IPFS CID of additional metadata (e.g., operational permissions, maintenance records)
        address owner;
    }

    // Mapping from token ID to UAV data
    mapping(uint256 => UAVData) public uavData;

    // Mapping from token ID to linked certificate NFTs
    mapping(uint256 => LinkedCertificate[]) public linkedCertificates; // Array of Certificate NFTs

    // Mapping from token ID to import/export trace
    mapping(uint256 => string[]) public importExportTrace; // Array of jurisdiction identifiers or CIDs

    // Events
    event UAVMinted(uint256 indexed tokenId, address indexed manufacturer, string ipfsMetadataCID);

    event CertificateLinked(uint256 indexed tokenId, CertificateTypes.CertificateType indexed ctype, address certificateContract, uint256 certificateTokenId);

    event OwnershipTransferred(uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner);

    // Modified event
    event ImportRejected(uint256 indexed tokenId, string reason);

    event MetadataUpdated(uint256 indexed tokenId, string ipfsMetadataCID);

    event ImportExportRecorded( uint256 indexed tokenId, string jurisdictionIdentifier);

    constructor() ERC721("UAVPassport", "UAVP") {
        tokenCounter = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Override supportsInterface due to multiple inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }


    modifier onlyManufacturer(){
        require(hasRole(MANUFACTURER_ROLE, msg.sender), "Caller is not a manufacturer");
        _;
    }

    modifier onlyAuthority() {
        require(hasRole(AUTHORITY_ROLE, msg.sender), "Caller is not an authority");
        _;
    }

    // Function to add a manufacturer
    function addManufacturer(address manufacturer) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        grantRole(MANUFACTURER_ROLE, manufacturer);
    }

    // Function to add a regulatory authority
    function addAuthority(address authority) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        grantRole(AUTHORITY_ROLE, authority);
    }

    // Manufacturer mints UAV NFT
    function mintUAV(string memory serialNumber, address typeCertificateContract,
        uint256 typeCertificateApplicationId,string memory ipfsMetadataCID) external onlyManufacturer {
        tokenCounter++;
        uint256 tokenId = tokenCounter;

        _safeMint(msg.sender, tokenId);

        // Store UAV data
        uavData[tokenId] = UAVData({
            tokenId: tokenId,
            serialNumber: serialNumber,
            typeCertificateContract: typeCertificateContract,
            typeCertificateApplicationId: typeCertificateApplicationId,
            ipfsMetadataCID: ipfsMetadataCID,
            owner: msg.sender
        });

        emit UAVMinted(tokenId, msg.sender, ipfsMetadataCID);
    }

    // Manufacturer updates UAV metadata (e.g., maintenance records)
    function updateMetadata(uint256 tokenId, string memory ipfsMetadataCID) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        UAVData storage data = uavData[tokenId];
        data.ipfsMetadataCID = ipfsMetadataCID;

        emit MetadataUpdated(tokenId, ipfsMetadataCID);
    }

    // Regulatory Authority links a certificate NFT to the UAV NFT
    function linkCertificate(uint256 uavTokenId, address certificateContractAddress, uint256 certificateTokenId) external onlyAuthority {
        require(_tokenExists(uavTokenId), "UAV token does not exist");

        // CertificateNFT interface
        CertificateNFTInterface certificate = CertificateNFTInterface(certificateContractAddress);

        // Ensure the caller is the owner of the CertificateNFT
        require(certificate.ownerOf(certificateTokenId) == msg.sender, "Caller is not the owner of the CertificateNFT");

        // Get the CertificateType from the CertificateNFT
        CertificateTypes.CertificateType ctype = certificate.getCertificateType(certificateTokenId);

        // Transfer the CertificateNFT to this contract
        certificate.safeTransferFrom(msg.sender, address(this), certificateTokenId);

        // Record the linked certificate
        linkedCertificates[uavTokenId].push(LinkedCertificate({
            certificateContract: certificateContractAddress,
            certificateTokenId: certificateTokenId,
            ctype: ctype
        }));

        emit CertificateLinked(uavTokenId, ctype, certificateContractAddress, certificateTokenId);
    }

    // Transfer UAV NFT ownership
    function transferUAV(address to, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        _transfer(msg.sender, to, tokenId);

        // Update owner in UAV data
        UAVData storage data = uavData[tokenId];
        address previousOwner = data.owner;
        data.owner = to;

        emit OwnershipTransferred(tokenId, previousOwner, to);
    }

    // Regulatory Authority records import rejection
    function rejectImport(uint256 tokenId, string memory reason) external onlyAuthority {
        require(_tokenExists(tokenId), "UAV token does not exist");
        // Record the rejection event without altering NFT transferability
        emit ImportRejected(tokenId, reason);
    }

    // Record import/export trace
    function recordImportExport(uint256 tokenId, string memory jurisdictionIdentifier) external onlyAuthority {
        require(_tokenExists(tokenId), "UAV token does not exist");
        importExportTrace[tokenId].push(jurisdictionIdentifier);

        emit ImportExportRecorded(tokenId, jurisdictionIdentifier);
    }

    // Retrieve UAV data
    function getUAVData(uint256 tokenId) external view returns (UAVData memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return uavData[tokenId];
    }

    // Retrieve linked certificates
    function getLinkedCertificates(uint256 tokenId) external view returns (LinkedCertificate[] memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return linkedCertificates[tokenId];
    }

    // Retrieve import/export trace
    function getImportExportTrace(uint256 tokenId) external view returns (string[] memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return importExportTrace[tokenId];
    }

    // Internal function to check if a token exists
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    // Implement IERC721Receiver to receive CertificateNFTs
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
