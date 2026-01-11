const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);

  const HyperliquidAggregator = await hre.ethers.getContractFactory("HyperliquidAggregator");
  const agg = await HyperliquidAggregator.deploy();
  await agg.waitForDeployment();

  console.log("HyperliquidAggregator:", agg.target);

  const attestors = (process.env.AGG_ALLOWED_ATTESTORS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  for (const addr of attestors) {
    const tx = await agg.setAttestorAllowed(addr, true);
    await tx.wait();
    console.log("allowed attestor:", addr);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
