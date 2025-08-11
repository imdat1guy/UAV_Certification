// Node.js benchmark for:
//   • UAVPassportNFT.mintUAV
//   • Airworthiness.submitApplication / completeInspection / issueCertificate
//   • CertificateNFT.mintCertificate  + linkCertificate
//
// Requires: ethers v5   ->   npm i ethers@5
//
// Usage example:
//
//   node bench_uav_air_cert.js \
//     --rpc  https://sepolia.infura.io/v3/<key> \
//     --passport 0xUAVPassportAddr \
//     --airworth 0xAirworthinessAddr \
//     --cert     0xCertificateNFTAddr \
//     --pk-reg 0x... --pk-mfr 0x... \
//     --type-cert 0xTypeCertContract \
//     --type-app-id 1   \
//     --n 500  --c 20 \
//     --run-id sepolia_W2_N500_C20_r1 \
//     --network sepolia --out benchmarks.csv
//
// ---------------------------------------------------------------------------

const fs = require('fs');
const { ethers } = require('ethers');

// ------------- Mini-ABIs (only the funcs/events we use) --------------------
const ABI_PASS = [
  // role mgmt
  "function MANUFACTURER_ROLE() view returns (bytes32)",
  "function AUTHORITY_ROLE() view returns (bytes32)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function addManufacturer(address) external",
  "function addAuthority(address) external",

  // core
  "function mintUAV(string,address,uint256,string) external",
  "function linkCertificate(uint256,address,uint256) external",

  // events
  "event UAVMinted(uint256 indexed tokenId,address indexed manufacturer,string ipfsMetadataCID)",
  "event CertificateLinked(uint256 indexed tokenId,uint8 indexed ctype,address certificateContract,uint256 certificateTokenId)"
];

const ABI_AIR = [
  "function submitApplication(address,uint256,string) external",
  "function completeInspection(uint256,string) external",
  "function issueCertificate(uint256,string) external",
  "event ApplicationSubmitted(uint256 indexed applicationId)",
  "event InspectionCompleted(uint256 indexed applicationId,string)",
  "event CertificateIssued(uint256 indexed applicationId,string)"
];

const ABI_CERT = [
  // role mgmt
  "function AUTHORITY_ROLE() view returns (bytes32)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function addAuthority(address) external",

  // mint + approve
  "function mintCertificate(string,uint8,address,address,uint256) external",
  "function approve(address,uint256) external",

  // queries for link step
  "function ownerOf(uint256) view returns (address)",

  // event
  "event CertificateMinted(uint256 indexed tokenId,uint8 indexed ctype,address issuer,string metadataURI)"
];
// ---------------------------------------------------------------------------

// ---- Helper for CLI args --------------------------------------------------
function arg(key, def = undefined) {
  const i = process.argv.indexOf(key);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}
const nowISO = () => new Date().toISOString();

// ---- CSV helpers ----------------------------------------------------------
function ensureCsv(path) {
  if (!fs.existsSync(path)) {
    fs.writeFileSync(
      path,
      [
        "run_id","network","rollup_type","workflow","op_type","uav_count","concurrency",
        "tx_hash","submitted_at_utc","included_at_utc","finalized_at_utc",
        "block_number","confirmations","gas_used","effective_gas_price_wei",
        "success","error","notes"
      ].join(",") + "\n"
    );
  }
}
function csvField(v) {
  if (v === undefined || v === null) return "";
  const s = String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
function appendCsv(path, row) {
  const headers = [
    "run_id","network","rollup_type","workflow","op_type","uav_count","concurrency",
    "tx_hash","submitted_at_utc","included_at_utc","finalized_at_utc",
    "block_number","confirmations","gas_used","effective_gas_price_wei",
    "success","error","notes"
  ];
  fs.appendFileSync(path, headers.map(h => csvField(row[h])).join(",") + "\n");
}
function serializeErr(e) {
  try { return JSON.stringify(e, Object.getOwnPropertyNames(e)); }
  catch { return String(e?.message || e); }
}

// ---- Main -----------------------------------------------------------------
async function main() {
  // ---- CLI / ENV ----------------------------------------------------------
  const RPC         = arg("--rpc")        || process.env.RPC_URL;
  const PASSPORT    = arg("--passport")   || process.env.PASSPORT_ADDR;
  const AIRWORTH    = arg("--airworth")   || process.env.AIR_ADDR;
  const CERTNFT     = arg("--cert")       || process.env.CERT_ADDR;
  const TYPE_CERT   = arg("--type-cert")  || "0x0000000000000000000000000000000000000000";
  const TYPE_APP_ID = parseInt(arg("--type-app-id","1"),10);

  const PK_REG = arg("--pk-reg") || process.env.PK_REG;
  const PK_MFR = arg("--pk-mfr") || process.env.PK_MFR;

  const N        = parseInt(arg("--n","50"),10);
  const CONC     = parseInt(arg("--c","10"),10);
  const CONFIRM  = parseInt(arg("--confs","0"),10);
  const RUN_ID   = arg("--run-id","run_passport_air_cert");
  const NET      = arg("--network","sepolia");
  const ROLLUP   = arg("--rollup","none");
  const OUTFILE  = arg("--out","benchmarks.csv");

  if (!RPC || !PASSPORT || !AIRWORTH || !CERTNFT || !PK_REG || !PK_MFR) {
    console.error("Missing required args.");
    process.exit(1);
  }
  ensureCsv(OUTFILE);

  // ---- Providers / Signers / Contracts -----------------------------------
  const provider = new ethers.providers.JsonRpcProvider(RPC);
  const reg = new ethers.Wallet(PK_REG, provider);
  const mfr = new ethers.Wallet(PK_MFR, provider);

  const pass = new ethers.Contract(PASSPORT, ABI_PASS, provider).connect(reg);
  const air  = new ethers.Contract(AIRWORTH, ABI_AIR,  provider).connect(reg);
  const cert = new ethers.Contract(CERTNFT, ABI_CERT,  provider).connect(reg);

  // ---- One-time role checks ----------------------------------------------
  async function ensureRole(c, roleFnName, addFnName, whoSigner, whoAddr) {
    const role = await c[roleFnName]();
    if (!(await c.hasRole(role, whoAddr))) {
      const tx = await c.connect(reg)[addFnName](whoAddr);
      await tx.wait();
    }
  }
  await ensureRole(pass,"MANUFACTURER_ROLE","addManufacturer",reg, mfr.address);
  await ensureRole(pass,"AUTHORITY_ROLE","addAuthority",   reg, reg.address);
  await ensureRole(cert,"AUTHORITY_ROLE","addAuthority",   reg, reg.address);

  // ---- Internal logger ----------------------------------------------------
  async function logTxBase(common, op_type, txProm, notes="") {
    const submitted_at_utc = nowISO();
    const tx  = await txProm;
    const rc  = await tx.wait();
    const blk = await provider.getBlock(rc.blockNumber);

    appendCsv(OUTFILE, {
      ...common, op_type,
      tx_hash: rc.transactionHash,
      submitted_at_utc,
      included_at_utc: new Date(blk.timestamp*1000).toISOString(),
      finalized_at_utc: "",
      block_number: rc.blockNumber,
      confirmations: rc.confirmations || 1,
      gas_used: rc.gasUsed.toString(),
      effective_gas_price_wei: rc.effectiveGasPrice?.toString() || "",
      success: rc.status, error: "", notes
    });
    if (CONFIRM > 0) {
      await provider.waitForTransaction(rc.transactionHash, CONFIRM);
      appendCsv(OUTFILE, {
        ...common, op_type: op_type + "_finality",
        tx_hash: rc.transactionHash,
        submitted_at_utc,
        included_at_utc: new Date(blk.timestamp*1000).toISOString(),
        finalized_at_utc: nowISO(),
        block_number: rc.blockNumber,
        confirmations: CONFIRM,
        gas_used: rc.gasUsed.toString(),
        effective_gas_price_wei: rc.effectiveGasPrice?.toString() || "",
        success: rc.status, error: ""
      });
    }
    return rc;
  }

  // ---- Workflow (Mint + Airworthiness + Cert) ----------------------------
  const ifacePass = new ethers.utils.Interface(ABI_PASS);
  const ifaceAir  = new ethers.utils.Interface(ABI_AIR);
  const ifaceCert = new ethers.utils.Interface(ABI_CERT);

  async function runWorkflow(idx) {
    const common = {
      run_id: RUN_ID, network: NET, rollup_type: ROLLUP,
      workflow: "W2", uav_count: N, concurrency: CONC
    };
    try {
      // 1. mintUAV (manufacturer)
      const rcMint = await logTxBase(
        common, "mintUAV",
        pass.connect(mfr).mintUAV(
          `SN-${Date.now()}-${idx}`,    // serial number
          TYPE_CERT, TYPE_APP_ID,
          "ipfs://uav_meta"
        )
      );
      const uavTokenId = ifacePass.parseLog(rcMint.logs.find(l=>l.topics[0]===ifacePass.getEventTopic("UAVMinted"))).args.tokenId.toString();

      // 2. submitApplication (mfr)
      const rcApp = await logTxBase(
        common,"submitAirworthiness",
        air.connect(mfr).submitApplication(PASSPORT, uavTokenId, "ipfs://aw_docs")
      );
      const appId = ifaceAir.parseLog(rcApp.logs[0]).args.applicationId.toString();

      // 3. completeInspection (reg)
      await logTxBase(common,"completeInspection", air.completeInspection(appId,"hash_inspection"));

      // 4. issueCertificate (reg)
      await logTxBase(common,"issueCertificate", air.issueCertificate(appId,"ipfs://aw_cert_meta"));

      // 5. mintCertificate (reg)   ctype = 0 (Airworthiness)
      const rcCert = await logTxBase(
        common,"mintCertificate",
        cert.mintCertificate("ipfs://aw_cert_meta", 0, reg.address, AIRWORTH, appId)
      );
      const certTokenId = ifaceCert.parseLog(rcCert.logs.find(l=>l.topics[0]===ifaceCert.getEventTopic("CertificateMinted"))).args.tokenId.toString();

      // 6. approve (reg) & linkCertificate (reg)
      await logTxBase(common,"approveCertNFT", cert.approve(PASSPORT, certTokenId));
      await logTxBase(common,"linkCertificate", pass.linkCertificate(uavTokenId, CERTNFT, certTokenId));

    } catch (e) {
      appendCsv(OUTFILE,{
        run_id: RUN_ID, network: NET, rollup_type: ROLLUP, workflow:"W2",
        op_type:"workflow_error", uav_count:N, concurrency:CONC,
        success:0, error: serializeErr(e)
      });
    }
  }

  // ---- Simple concurrency loop -------------------------------------------
  const queue = [];
  let active = 0;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const t0 = Date.now();

  for (let i = 0; i < N; i++) {
    const task = (async () => {
      while (active >= CONC) await sleep(5);
      active++;
      await runWorkflow(i);
      active--;
    })();
    queue.push(task);
  }
  await Promise.all(queue);
  console.log(`Finished ${N} W2 workflows in ${(Date.now() - t0)/1000}s`);
}

main().catch(err => { console.error(err); process.exit(1); });
