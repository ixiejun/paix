const hre = require("hardhat");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isConnectTimeout(err) {
  const msg = (err && err.message) ? err.message : "";
  return err && (err.code === "UND_ERR_CONNECT_TIMEOUT" || msg.includes("Connect Timeout"));
}

async function withRetry(label, fn, { retries = 6, baseDelayMs = 1500 } = {}) {
  let lastErr;
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      if (!isConnectTimeout(e) || i === retries - 1) {
        throw e;
      }
      const delay = baseDelayMs * Math.pow(2, i);
      console.log(`[retry] ${label} failed with ConnectTimeout, retrying in ${delay}ms (attempt ${i + 2}/${retries})`);
      await sleep(delay);
    }
  }
  throw lastErr;
}

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0];

  console.log("Network:", hre.network.name);
  console.log("Deployer:", deployer.address);

  const TestERC20 = await hre.ethers.getContractFactory("TestERC20");

  let baseToken = process.env.SMOKE_BASE_TOKEN;
  let quoteToken = process.env.SMOKE_QUOTE_TOKEN;
  let orderBookAddr = process.env.SMOKE_ORDERBOOK;

  if (!baseToken || !quoteToken) {
    const base = await withRetry("deploy base token", () => TestERC20.deploy(
      "CLOB Smoke Base",
      "CS_BASE",
      hre.ethers.parseUnits("1000000", 18)
    ));
    await withRetry("wait base token", () => base.waitForDeployment());

    const quote = await withRetry("deploy quote token", () => TestERC20.deploy(
      "CLOB Smoke Quote",
      "CS_QUOTE",
      hre.ethers.parseUnits("1000000", 18)
    ));
    await withRetry("wait quote token", () => quote.waitForDeployment());

    baseToken = base.target;
    quoteToken = quote.target;
  }

  console.log("baseToken:", baseToken);
  console.log("quoteToken:", quoteToken);

  const matcher = deployer.address;
  const feeRecipient = deployer.address;
  const feeBps = 50; // 0.50%

  const OrderBook = await hre.ethers.getContractFactory("OrderBook");
  const ob = orderBookAddr
    ? OrderBook.attach(orderBookAddr)
    : await withRetry("deploy OrderBook", () => OrderBook.deploy(baseToken, quoteToken, matcher, feeRecipient, feeBps));

  if (!orderBookAddr) {
    await withRetry("wait OrderBook", () => ob.waitForDeployment());
    orderBookAddr = ob.target;
  }

  console.log("OrderBook:", orderBookAddr);
  console.log("matcher:", matcher);
  console.log("feeRecipient:", feeRecipient);
  console.log("feeBps:", feeBps);

  // deposit both sides for a self-crossing trade (single funded account on testnet)
  const depositBase = hre.ethers.parseUnits("100", 18);
  const depositQuote = hre.ethers.parseUnits("1000", 18);

  const base = TestERC20.attach(baseToken);
  const quote = TestERC20.attach(quoteToken);

  let tx = await withRetry("approve base", () => base.approve(orderBookAddr, depositBase));
  console.log("approve base tx:", tx.hash);
  await withRetry("wait approve base", () => tx.wait());

  tx = await withRetry("deposit base", () => ob.deposit(baseToken, depositBase));
  console.log("deposit base tx:", tx.hash);
  await withRetry("wait deposit base", () => tx.wait());

  tx = await withRetry("approve quote", () => quote.approve(orderBookAddr, depositQuote));
  console.log("approve quote tx:", tx.hash);
  await withRetry("wait approve quote", () => tx.wait());

  tx = await withRetry("deposit quote", () => ob.deposit(quoteToken, depositQuote));
  console.log("deposit quote tx:", tx.hash);
  await withRetry("wait deposit quote", () => tx.wait());

  const buyPrice = hre.ethers.parseUnits("2", 18);
  const sellPrice = hre.ethers.parseUnits("1.5", 18);
  const baseAmount = hre.ethers.parseUnits("10", 18);

  tx = await withRetry("placeBuy", () => ob.placeBuy(buyPrice, baseAmount));
  console.log("placeBuy tx:", tx.hash);
  const rBuy = await withRetry("wait placeBuy", () => tx.wait());
  const buyEvt = rBuy.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced");
  const buyOrderId = buyEvt.args.orderId;
  console.log("buyOrderId:", buyOrderId.toString());

  tx = await withRetry("placeSell", () => ob.placeSell(sellPrice, baseAmount));
  console.log("placeSell tx:", tx.hash);
  const rSell = await withRetry("wait placeSell", () => tx.wait());
  const sellEvt = rSell.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced");
  const sellOrderId = sellEvt.args.orderId;
  console.log("sellOrderId:", sellOrderId.toString());

  tx = await withRetry("matchOrders", () => ob.matchOrders(buyOrderId, sellOrderId, baseAmount, sellPrice));
  console.log("matchOrders tx:", tx.hash);
  await withRetry("wait matchOrders", () => tx.wait());

  const baseAvail = await withRetry("read available base", () => ob.available(deployer.address, baseToken));
  const quoteAvail = await withRetry("read available quote", () => ob.available(deployer.address, quoteToken));

  console.log("available base:", baseAvail.toString());
  console.log("available quote:", quoteAvail.toString());

  // withdraw a small amount to prove end-to-end
  const withdrawQuote = hre.ethers.parseUnits("1", 18);
  tx = await withRetry("withdraw quote", () => ob.withdraw(quoteToken, withdrawQuote));
  console.log("withdraw quote tx:", tx.hash);
  await withRetry("wait withdraw quote", () => tx.wait());

  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
