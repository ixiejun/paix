const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);

  const GasSponsorForwarder = await hre.ethers.getContractFactory("GasSponsorForwarder");
  const forwarder = await GasSponsorForwarder.deploy();
  await forwarder.waitForDeployment();

  console.log("GasSponsorForwarder:", forwarder.target);

  const requireAllowlist = process.env.SPONSOR_REQUIRE_ALLOWLIST === "true";
  if (requireAllowlist) {
    const tx = await forwarder.setRequireRelayerAllowed(true);
    await tx.wait();
    console.log("requireRelayerAllowed: true");

    const allowed = (process.env.SPONSOR_ALLOWED_RELAYERS || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);

    for (const addr of allowed) {
      const t = await forwarder.setRelayerAllowed(addr, true);
      await t.wait();
      console.log("allowed relayer:", addr);
    }
  } else {
    console.log("requireRelayerAllowed: false");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
