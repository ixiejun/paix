const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);

  // If BASE_TOKEN / QUOTE_TOKEN are not provided, deploy local TestERC20 tokens
  let baseToken = process.env.BASE_TOKEN;
  let quoteToken = process.env.QUOTE_TOKEN;

  if (!baseToken || !quoteToken) {
    const TestERC20 = await hre.ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy(
      "CLOB Base",
      "CLOB_BASE",
      hre.ethers.parseUnits("1000000", 18)
    );
    await base.waitForDeployment();

    const quote = await TestERC20.deploy(
      "CLOB Quote",
      "CLOB_QUOTE",
      hre.ethers.parseUnits("1000000", 18)
    );
    await quote.waitForDeployment();

    baseToken = base.target;
    quoteToken = quote.target;
  }

  const matcher = process.env.CLOB_MATCHER || deployer.address;
  const feeRecipient = process.env.CLOB_FEE_RECIPIENT || deployer.address;
  const feeBps = process.env.CLOB_FEE_BPS ? Number(process.env.CLOB_FEE_BPS) : 50; // 0.50%

  const OrderBook = await hre.ethers.getContractFactory("OrderBook");
  const ob = await OrderBook.deploy(baseToken, quoteToken, matcher, feeRecipient, feeBps);
  await ob.waitForDeployment();

  console.log("baseToken:", baseToken);
  console.log("quoteToken:", quoteToken);
  console.log("OrderBook:", ob.target);
  console.log("matcher:", matcher);
  console.log("feeRecipient:", feeRecipient);
  console.log("feeBps:", feeBps);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
