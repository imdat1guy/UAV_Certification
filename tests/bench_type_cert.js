// bench_type_cert.js
// Node.js script to benchmark the TypeCertificate workflow on a public RPC
// Requires: ethers v5   ->   npm i ethers@5
// Usage example:
//   node bench_type_cert.js \
//     --rpc https://sepolia.infura.io/v3/<key> \
//     --addr 0xTypeCertAddr \
//     --pk-reg 0x... --pk-mfr 0x... --pk-nb 0x... \
//     --n 1000 --c 25 --confs 5 \
//     --run-id sepolia_W1_N1000_C25_r1 \
//     --network sepolia --rollup optimistic \
//     --out benchmarks.csv

const fs = require('fs');
const { ethers } = require('ethers'); // v5

// Minimal ABI: functions + events used here
// Minimal ABI for TypeCertificate (functions + events you use)
const ABI = [
  // functions
  "function submitApplication(string ipfsDirectoryCID, bytes32 droneSpecDocumentHash) external",
  "function updateDocuments(uint256 applicationId, string updatedIpfsDirectoryCID, bytes32 updatedDroneSpecDocumentHash) external",
  "function approveDocuments(uint256 applicationId, string certificationSpecificationsCID) external",
  "function authorizeNotifiedBody(address nb) external",
  "function revokeNotifiedBody(address nb) external",
  "function requestTypeExamination(uint256 applicationId, string internalReportCID) external",
  "function completeInspection(uint256 applicationId, string notifiedBodyReportCID) external",
  "function issueCertificate(uint256 applicationId, string typeCertificateCID) external",
  "function rejectApplication(uint256 applicationId) external",

  // events (note the extra args vs your earlier script)
  "event NotifiedBodyAuthorized(address indexed notifiedBody)",
  "event NotifiedBodyRevoked(address indexed notifiedBody)",

  "event ApplicationSubmitted(uint256 indexed applicationId, address indexed manufacturer)",
  "event DocumentsUpdated(uint256 indexed applicationId)",
  "event DocumentsApproved(uint256 indexed applicationId, string csCID)",

  "event ExaminationRequested(uint256 indexed applicationId, string internalReportCID)",
  "event InspectionCompleted(uint256 indexed applicationId, address notifiedBody)",

  "event ApplicationRejected(uint256 indexed applicationId)",
  "event CertificateIssued(uint256 indexed applicationId, string ipfsHashCertificate)"
];


function arg(key, def = undefined) {
  const idx = process.argv.indexOf(key);
  if (idx !== -1 && process.argv[idx+1]) return process.argv[idx+1];
  return def;
}
const nowISO = () => new Date().toISOString();

function ensureCsv(path) {
  if (!fs.existsSync(path)) {
    fs.writeFileSync(path,
      [
        'run_id','network','rollup_type','workflow','op_type','uav_count','concurrency',
        'tx_hash','submitted_at_utc','included_at_utc','finalized_at_utc',
        'block_number','confirmations','gas_used','effective_gas_price_wei',
        'success','error','notes'
      ].join(',') + '\n'
    );
  }
}
function appendCsv(path, row) {
  const headers = [
    'run_id','network','rollup_type','workflow','op_type','uav_count','concurrency',
    'tx_hash','submitted_at_utc','included_at_utc','finalized_at_utc',
    'block_number','confirmations','gas_used','effective_gas_price_wei',
    'success','error','notes'
  ];
  const line = headers.map(h => row[h] !== undefined ? String(row[h]) : '').join(',') + '\n';
  fs.appendFileSync(path, line);
}

async function main() {
  const RPC_URL = arg('--rpc') || process.env.RPC_URL;
  const TYPE_CERT_ADDR = arg('--addr') || process.env.TYPE_CERT_ADDR;
  const PK_REG = arg('--pk-reg') || process.env.PK_REG;
  const PK_MFR = arg('--pk-mfr') || process.env.PK_MFR;
  const PK_NB  = arg('--pk-nb')  || process.env.PK_NB;
  const RUN_ID = arg('--run-id', 'run1');
  const NETWORK = arg('--network', 'sepolia');
  const ROLLUP = arg('--rollup', 'none');
  const OUT = arg('--out', 'benchmarks.csv');
  const N = parseInt(arg('--n','100'),10);
  const CONC = parseInt(arg('--c','10'),10);
  const CONFIRMATIONS = parseInt(arg('--confs','0'),10); // 0 = inclusion only

  if (!RPC_URL || !TYPE_CERT_ADDR || !PK_REG || !PK_MFR || !PK_NB) {
    console.error('Missing required args: --rpc --addr --pk-reg --pk-mfr --pk-nb');
    process.exit(1);
  }

  ensureCsv(OUT);

  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const reg = new ethers.Wallet(PK_REG, provider);
  const mfr = new ethers.Wallet(PK_MFR, provider);
  const nb  = new ethers.Wallet(PK_NB,  provider);

  const contractReg = new ethers.Contract(TYPE_CERT_ADDR, ABI, reg);
  const contractMfr = new ethers.Contract(TYPE_CERT_ADDR, ABI, mfr);
  const contractNb  = new ethers.Contract(TYPE_CERT_ADDR, ABI, nb);

  // Authorize notified body once (idempotent at app level)
  try {
    const subTS = nowISO();
    const tx = await contractReg.authorizeNotifiedBody(await nb.getAddress());
    const rc = await tx.wait();
    const blk = await provider.getBlock(rc.blockNumber);
    appendCsv(OUT, {
      run_id: RUN_ID, network: NETWORK, rollup_type: ROLLUP,
      workflow: 'W1', op_type: 'authorizeNotifiedBody', uav_count: N, concurrency: CONC,
      tx_hash: rc.transactionHash,
      submitted_at_utc: subTS,
      included_at_utc: new Date(blk.timestamp*1000).toISOString(),
      finalized_at_utc: '',
      block_number: rc.blockNumber,
      confirmations: rc.confirmations || 1,
      gas_used: rc.gasUsed.toString(),
      effective_gas_price_wei: rc.effectiveGasPrice ? rc.effectiveGasPrice.toString() : '',
      success: rc.status, error: ''
    });
  } catch (e) {
    console.warn('authorizeNotifiedBody skipped:', e.message);
  }

  const iface = new ethers.utils.Interface(ABI);

  async function logTx(common, op_type, txPromise, notes='') {
    const submitted_at_utc = nowISO();
    const tx = await txPromise;
    const rc = await tx.wait();
    const blk = await provider.getBlock(rc.blockNumber);
    appendCsv(OUT, {
      ...common, op_type,
      tx_hash: rc.transactionHash,
      submitted_at_utc,
      included_at_utc: new Date(blk.timestamp*1000).toISOString(),
      finalized_at_utc: '',
      block_number: rc.blockNumber,
      confirmations: rc.confirmations || 1,
      gas_used: rc.gasUsed.toString(),
      effective_gas_price_wei: rc.effectiveGasPrice ? rc.effectiveGasPrice.toString() : '',
      success: rc.status, error: '', notes
    });
    if (CONFIRMATIONS > 0) {
      await provider.waitForTransaction(rc.transactionHash, CONFIRMATIONS);
      const b2 = await provider.getBlock(rc.blockNumber + Math.max(CONFIRMATIONS-1,0));
      appendCsv(OUT, {
        ...common, op_type: op_type + '_finality',
        tx_hash: rc.transactionHash,
        submitted_at_utc,
        included_at_utc: new Date(blk.timestamp*1000).toISOString(),
        finalized_at_utc: b2 ? new Date(b2.timestamp*1000).toISOString() : '',
        block_number: rc.blockNumber,
        confirmations: CONFIRMATIONS,
        gas_used: rc.gasUsed.toString(),
        effective_gas_price_wei: rc.effectiveGasPrice ? rc.effectiveGasPrice.toString() : '',
        success: rc.status, error: ''
      });
    }
    return rc;
  }

  async function oneWorkflow(i) {
    const common = { run_id: RUN_ID, network: NETWORK, rollup_type: ROLLUP, workflow: 'W1', uav_count: N, concurrency: CONC };
    // 1) submitApplication (manufacturer)
    let rc1 = await logTx(common, 'submitApplication',
      contractMfr.submitApplication('ipfs://initial-docs', ethers.utils.keccak256(ethers.utils.toUtf8Bytes('drone-spec')))
    );
    // Extract applicationId from logs
    let appId = null;
    for (const log of rc1.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed && parsed.name === 'ApplicationSubmitted') { appId = parsed.args.applicationId.toString(); break; }
      } catch (_) {}
    }
    if (!appId) throw new Error('Missing applicationId from ApplicationSubmitted');

    // 2) approveDocuments (regulator)
    await logTx(common, 'approveDocuments', contractReg.approveDocuments(appId, 'ipfs://certification-specs'));

    // 3) requestTypeExamination (manufacturer)
    await logTx(common, 'requestTypeExamination', contractMfr.requestTypeExamination(appId, 'ipfs://internal-report'));

    // 4) completeInspection (notified body)
    await logTx(common, 'completeInspection', contractNb.completeInspection(appId, 'ipfs://inspection-report'));

    // 5) issueCertificate (regulator)
    await logTx(common, 'issueCertificate', contractReg.issueCertificate(appId, 'ipfs://final-certificate'));
  }

  // Simple concurrency control
  const tasks = [];
  let active = 0;
  const sleep = ms => new Promise(r=>setTimeout(r,ms));
  const t0 = Date.now();
  for (let i=0; i<N; i++) {
    const go = (async () => {
      while (active >= CONC) await sleep(5);
      active++;
      try { await oneWorkflow(i); }
      catch (e) {
        appendCsv(OUT, {
          run_id: RUN_ID, network: NETWORK, rollup_type: ROLLUP, workflow: 'W1',
          op_type: 'workflow_error', uav_count: N, concurrency: CONC, success: 0, error: e.message
        });
      } finally { active--; }
    })();
    tasks.push(go);
  }
  await Promise.all(tasks);
  const t1 = Date.now();
  console.log(`Completed ${N} workflows at concurrency=${CONC} in ${(t1 - t0)/1000}s`);
}

main().catch(e => { console.error(e); process.exit(1); });
