const { ethers } = require("hardhat");

const ENUM = { Airworthiness: 0, Export: 1, Import: 2 };
const PROFILE = ethers.id("PROFILE:EASA-CERTIFIED-V1");
const CONTROLS_HASH = ethers.ZeroHash;

async function deployStack() {
  const [authority, manufacturer] = await ethers.getSigners();

  // UAVPassport
  const UAV = await ethers.getContractFactory("UAVPassportNFT", authority);
  const uav = await UAV.deploy();
  await uav.waitForDeployment();

  await (await uav.addManufacturer(manufacturer.address)).wait();
  await (await uav.addAuthority(authority.address)).wait();

  // ERC-721 CertificateNFT
  const Cert721F = await ethers.getContractFactory("CertificateNFT", authority);
  const cert721 = await Cert721F.deploy();
  await cert721.waitForDeployment();
  await (await cert721.addAuthority(authority.address)).wait();

  // ERC-1155 Certificate1155
  const Cert1155F = await ethers.getContractFactory("Certificate1155", authority);
  const cert1155 = await Cert1155F.deploy();
  await cert1155.waitForDeployment();
  await (await cert1155.addAuthority(authority.address)).wait();

  // Manufacturer mints a UAV passport
  const serial = "SN-0001";
  const typeCertContract = ethers.ZeroAddress; // not used in gas test
  const typeCertAppId = 0;
  const metaCID = "QmUAVMetadata";
  let tx = await uav.connect(manufacturer).mintUAV(
    serial, typeCertContract, typeCertAppId, metaCID
  );
  await tx.wait();
  // v6: read the counter instead of parsing event
  const uavTokenId = Number(await uav.tokenCounter());

  // Approve once for both standards
  await (await cert721.connect(authority).setApprovalForAll(await uav.getAddress(), true)).wait();
  await (await cert1155.connect(authority).setApprovalForAll(await uav.getAddress(), true)).wait();

  return { authority, manufacturer, uav, cert721, cert1155, uavTokenId };
}

// ---------- Helpers (bigint) ----------
const ZERO = 0n;
const toStr = (x) => x.toString();

// ---------- ERC-721 path ----------
async function run721(N, ctx) {
  const { authority, uav, cert721, uavTokenId } = ctx;
  let totalMint = ZERO;
  let totalLink = ZERO;
  const ids = [];

  for (let i = 0; i < N; i++) {
    const tx = await cert721.connect(authority).mintCertificate(
      "ipfs://certMeta",     // metadataURI
      ENUM.Export,           // Export to avoid airworthiness checks
      authority.address,     // issuer
      ethers.ZeroAddress,    // linkedContract (unused here)
      0,                     // linkedApplicationId
      PROFILE,
      CONTROLS_HASH
    );
    const rc = await tx.wait();
    totalMint += rc.gasUsed;

    // Read the counter instead of parsing the event
    const id = Number(await cert721.certificateCounter());
    ids.push(id);
  }

  for (const id of ids) {
    const tx = await uav.connect(authority).linkCertificate(
      uavTokenId, await cert721.getAddress(), id
    );
    const rc = await tx.wait();
    totalLink += rc.gasUsed;
  }

  return { totalMint, totalLink, ids };
}

// ---------- ERC-1155 path ----------
async function run1155(N, ctx) {
  const { authority, uav, cert1155, uavTokenId } = ctx;

  // Read the starting id, build the list of ids that will be minted
  const start = await cert1155.nextId();                 // bigint
  const ids = Array.from({ length: N }, (_, i) => start + BigInt(i));

  // Batch-mint (1 tx)
  const mintTx = await cert1155
    .connect(authority)
    .mintBatchCertificates(N, ENUM.Export, authority.address, PROFILE, CONTROLS_HASH);
  const mintRc = await mintTx.wait();
  const mintGas = mintRc.gasUsed;

  // Batch-link (1 tx)
  const linkTx = await uav
    .connect(authority)
    .linkCertificates1155Batch(uavTokenId, await cert1155.getAddress(), ids);
  const linkRc = await linkTx.wait();
  const linkGas = linkRc.gasUsed;

  return { mintGas, linkGas, ids: ids.map(Number) };
}


async function main() {
  const batchSizes = [1, 5, 10, 50, 100];
  const rows = [];

  for (const N of batchSizes) {
    const ctx = await deployStack();

    const r721 = await run721(N, ctx);
    const gas721Total = r721.totalMint + r721.totalLink;
    const gas721Per = gas721Total / BigInt(N);

    const r1155 = await run1155(N, ctx);
    const gas1155Total = r1155.mintGas + r1155.linkGas;
    const gas1155Per = gas1155Total / BigInt(N);

    const savingsPer = gas721Per - gas1155Per;

    rows.push({
      N,
      gas721Total: toStr(gas721Total),
      gas721Per:   toStr(gas721Per),
      gas1155Total: toStr(gas1155Total),
      gas1155Per:   toStr(gas1155Per),
      savingsPer:   toStr(savingsPer),
    });
  }

  console.log("\n| Batch size (N) | ERC-721 total gas | ERC-721 per cert | ERC-1155 total gas | ERC-1155 per cert | Savings per cert |");
  console.log("| -------------: | ----------------: | ---------------: | -----------------: | ----------------: | ---------------: |");
  for (const r of rows) {
    console.log(`| ${String(r.N).padStart(13)} | ${r.gas721Total.padStart(16)} | ${r.gas721Per.padStart(15)} | ${r.gas1155Total.padStart(17)} | ${r.gas1155Per.padStart(16)} | ${r.savingsPer.padStart(15)} |`);
  }
  console.log();
}

main().catch((e) => { console.error(e); process.exit(1); });
