// PayDay frontend — read-only by default; writes need MetaMask.
// Contracts (testnet only):
const REACTIVE_ADDR = "0x47800f60e6b135813Ff3fa68fe3cD3AF50C6264f"; // Reactive Lasna
const PAYER_ADDR = "0x68be47672e809c7803c508451f66ba2907f210d5";    // Base Sepolia
const LASNA_RPC = "https://lasna-rpc.rnk.dev/";
const BASE_RPC = "https://base-sepolia.gateway.tenderly.co"; // sepolia.base.org limits eth_getLogs to 200 blocks; publicnode blocks CORS; Tenderly public gateway allows wide ranges + CORS *
const LASNA_CHAIN_ID = 5318007n;
const BASE_CHAIN_ID = 84532n;

const REACTIVE_ABI = [
  "function planCount() view returns (uint256)",
  "function plans(uint256) view returns (address owner, address recipient, uint256 amount, uint256 intervalSeconds, uint256 nextDue, bool active)",
  "function payer() view returns (address)",
  "function owner() view returns (address)",
  "function createPlan(address recipient, uint256 amount, uint256 intervalSeconds) returns (uint256)",
  "function cancelPlan(uint256 planId)",
  "event PlanCreated(uint256 indexed planId, address indexed owner, address indexed recipient, uint256 amount, uint256 intervalSeconds, uint256 nextDue)",
  "event PaymentRequested(uint256 indexed planId, address indexed recipient, uint256 amount)",
];
const PAYER_ABI = [
  "function fund() payable",
  "event Paid(uint256 indexed planId, address indexed recipient, uint256 amount)",
  "event PaymentSkipped(uint256 indexed planId, address indexed recipient, uint256 amount, string reason)",
  "event Funded(address indexed from, uint256 amount)",
];

const $ = (id) => document.getElementById(id);
const short = (a) => a ? a.slice(0, 6) + "…" + a.slice(-4) : "—";
const fmtEth = (wei) => { const s = Number(ethers.formatEther(wei)).toFixed(6).replace(/\.?0+$/, ""); return s === "" ? "0" : s; };
const fmtTime = (ts) => {
  const d = new Date(Number(ts) * 1000);
  return d.toLocaleString() + (Number(ts) * 1000 > Date.now() ? " (in " + Math.max(0, Math.round((Number(ts) * 1000 - Date.now()) / 1000)) + "s)" : " (due)");
};

let lasna, base, reactive, payer;
let signer = null, signerAddr = null, signerChain = null;

function showError(msg) {
  const box = $("errorBox");
  box.hidden = false;
  box.textContent = "⚠️ " + msg;
  console.error(msg);
}

async function loadAll() {
  $("plansStatus").textContent = "Loading plans…";
  $("activityStatus").textContent = "Loading events…";
  try {
    lasna = new ethers.JsonRpcProvider(LASNA_RPC);
    base = new ethers.JsonRpcProvider(BASE_RPC);
    reactive = new ethers.Contract(REACTIVE_ADDR, REACTIVE_ABI, lasna);
    payer = new ethers.Contract(PAYER_ADDR, PAYER_ABI, base);

    // Balances
    const [escrow, rBal] = await Promise.all([
      base.getBalance(PAYER_ADDR),
      lasna.getBalance(REACTIVE_ADDR),
    ]);
    $("escrow").textContent = fmtEth(escrow);
    $("reactiveBal").textContent = fmtEth(rBal);

    // Plans
    const count = Number(await reactive.planCount());
    const tbody = $("plansBody");
    tbody.innerHTML = "";
    if (count === 0) {
      $("plansStatus").textContent = "No plans yet — create the first one below.";
    } else {
      $("plansStatus").textContent = count + " plan(s) on-chain.";
      for (let i = 0; i < count; i++) {
        const p = await reactive.plans(i);
        const tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + i + "</td>" +
          "<td><code title=\"" + p.recipient + "\">" + short(p.recipient) + "</code></td>" +
          "<td>" + fmtEth(p.amount) + " ETH</td>" +
          "<td>" + p.intervalSeconds + "s</td>" +
          "<td>" + fmtTime(p.nextDue) + "</td>" +
          "<td>" + (p.active ? "✅ active" : "❌ cancelled") + "</td>";
        tbody.appendChild(tr);
      }
    }

    // Recent activity (bounded log range so public RPCs stay happy)
    await loadActivity();
    $("lastRefresh").textContent = new Date().toLocaleTimeString();
  } catch (e) {
    showError("Could not load on-chain data: " + (e && e.message ? e.message : e));
    $("plansStatus").textContent = "Failed to load — check your connection and refresh.";
    $("activityStatus").textContent = "Failed to load.";
  }
}

async function loadActivity() {
  const list = $("activityList");
  list.innerHTML = "";
  try {
    const [baseBlock, lasnaBlock] = await Promise.all([base.getBlockNumber(), lasna.getBlockNumber()]);
    const span = 10000;
    let failed = 0;
    const safe = (p) => p.catch((e) => { failed++; console.error(e); return []; });
    const [paidLogs, skipLogs, createdLogs, reqLogs] = await Promise.all([
      safe(payer.queryFilter(payer.filters.Paid, Math.max(0, baseBlock - span), baseBlock)),
      safe(payer.queryFilter(payer.filters.PaymentSkipped, Math.max(0, baseBlock - span), baseBlock)),
      safe(reactive.queryFilter(reactive.filters.PlanCreated, Math.max(0, lasnaBlock - span), lasnaBlock)),
      safe(reactive.queryFilter(reactive.filters.PaymentRequested, Math.max(0, lasnaBlock - span), lasnaBlock)),
    ]);
    const items = [];
    for (const l of paidLogs) items.push({ block: l.blockNumber, chain: "Base Sepolia", text: "💸 Paid plan #" + l.args.planId + " — " + fmtEth(l.args.amount) + " ETH to " + short(l.args.recipient), tx: l.transactionHash, explorer: "https://sepolia.basescan.org/tx/" });
    for (const l of skipLogs) items.push({ block: l.blockNumber, chain: "Base Sepolia", text: "⏭️ Skipped plan #" + l.args.planId + " — " + l.args.reason, tx: l.transactionHash, explorer: "https://sepolia.basescan.org/tx/" });
    for (const l of createdLogs) items.push({ block: l.blockNumber, chain: "Lasna", text: "📅 Plan #" + l.args.planId + " created — " + fmtEth(l.args.amount) + " ETH every " + l.args.intervalSeconds + "s to " + short(l.args.recipient), tx: l.transactionHash, explorer: "https://lasna.reactscan.net/tx/" });
    for (const l of reqLogs) items.push({ block: l.blockNumber, chain: "Lasna", text: "⚡ Payment requested for plan #" + l.args.planId + " — " + fmtEth(l.args.amount) + " ETH to " + short(l.args.recipient), tx: l.transactionHash, explorer: "https://lasna.reactscan.net/tx/" });
    items.sort((a, b) => b.block - a.block);
    // Automation state heuristic: a PaymentRequested event in the last ~500
    // Lasna blocks (~8 min) means CRON ticks are firing; otherwise paused/idle.
    const lastReq = reqLogs.length ? Math.max(...reqLogs.map((l) => l.blockNumber)) : 0;
    $("automation").textContent = (lastReq && lasnaBlock - lastReq <= 500)
      ? "✅ Running — last CRON payment request at Lasna block " + lastReq
      : "⏸ Paused or idle — no CRON payment request in the last ~500 Lasna blocks";
    if (items.length === 0) {
      $("activityStatus").textContent = "No events in the last 10,000 blocks." + (failed ? " (" + failed + " query/queries failed — see console.)" : "");
      return;
    }
    $("activityStatus").textContent = items.length + " event(s) in the last 10,000 blocks." + (failed ? " (" + failed + " query/queries failed — list may be incomplete.)" : "");
    for (const it of items.slice(0, 20)) {
      const li = document.createElement("li");
      li.innerHTML = "<strong>[" + it.chain + "]</strong> " + it.text +
        " <a href=\"" + it.explorer + it.tx + "\" target=\"_blank\" rel=\"noopener\">tx ↗</a>";
      list.appendChild(li);
    }
  } catch (e) {
    $("activityStatus").textContent = "Could not load events.";
    console.error(e);
  }
}

async function connectWallet() {
  if (!window.ethereum) {
    showError("No wallet found — install MetaMask to create plans or fund the escrow.");
    return;
  }
  try {
    const provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    signerAddr = await signer.getAddress();
    const net = await provider.getNetwork();
    signerChain = net.chainId;
    $("walletAddr").textContent = "Connected: " + short(signerAddr) + " (chain " + signerChain + ")";
    updateButtons();
  } catch (e) {
    showError("Wallet connection failed: " + (e && e.message ? e.message : e));
  }
}

function updateButtons() {
  $("createBtn").disabled = !(signer && signerChain === LASNA_CHAIN_ID);
  $("fundBtn").disabled = !(signer && signerChain === BASE_CHAIN_ID);
  $("createMsg").textContent = signer
    ? (signerChain === LASNA_CHAIN_ID ? "Ready — you are on Lasna." : "Switch your wallet to Reactive Lasna (5318007) to create a plan.")
    : "Connect a wallet to create a plan.";
  $("fundMsg").textContent = signer
    ? (signerChain === BASE_CHAIN_ID ? "Ready — you are on Base Sepolia." : "Switch your wallet to Base Sepolia (84532) to fund the escrow.")
    : "Connect a wallet to fund the escrow.";
}

$("connectBtn").addEventListener("click", connectWallet);
$("refreshBtn").addEventListener("click", loadAll);

$("createForm").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  if (!signer || signerChain !== LASNA_CHAIN_ID) { showError("Connect a wallet on Reactive Lasna first."); return; }
  const recipient = $("inRecipient").value.trim();
  const amount = $("inAmount").value;
  const interval = $("inInterval").value;
  try {
    $("createMsg").textContent = "Sending transaction…";
    const c = new ethers.Contract(REACTIVE_ADDR, REACTIVE_ABI, signer);
    const tx = await c.createPlan(recipient, ethers.parseEther(amount), BigInt(interval));
    $("createMsg").textContent = "⏳ Waiting for confirmation: " + tx.hash;
    await tx.wait();
    $("createMsg").textContent = "✅ Plan created! Tx: " + tx.hash;
    loadAll();
  } catch (e) {
    showError("Create plan failed: " + (e && e.message ? e.message : e));
  }
});

$("fundForm").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  if (!signer || signerChain !== BASE_CHAIN_ID) { showError("Connect a wallet on Base Sepolia first."); return; }
  const amount = $("inFund").value;
  try {
    $("fundMsg").textContent = "Sending transaction…";
    const c = new ethers.Contract(PAYER_ADDR, PAYER_ABI, signer);
    const tx = await c.fund({ value: ethers.parseEther(amount) });
    $("fundMsg").textContent = "⏳ Waiting for confirmation: " + tx.hash;
    await tx.wait();
    $("fundMsg").textContent = "✅ Escrow funded! Tx: " + tx.hash;
    loadAll();
  } catch (e) {
    showError("Fund failed: " + (e && e.message ? e.message : e));
  }
});

window.addEventListener("load", () => {
  updateButtons();
  loadAll();
  setInterval(loadAll, 60000); // auto-refresh every minute
});
