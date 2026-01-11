const hre = require("hardhat");

const DEFAULT_DEPLOYED = {
  weth: "0x4042196503b0C1E1f4188277bFfA46373FCf3576",
  factory: "0xdCB1Bc3F7b806E553FC79E48768c809c051734Ef",
  router: "0x9aeAf6995b64A490fe1c2a8c06Dc2E912a487710",
};

function envAddress(key, fallback) {
  const v = (process.env[key] || "").trim();
  return v || fallback;
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  const deployed = {
    weth: envAddress("UNISWAP_WETH9", DEFAULT_DEPLOYED.weth),
    factory: envAddress("UNISWAP_FACTORY", DEFAULT_DEPLOYED.factory),
    router: envAddress("UNISWAP_ROUTER", DEFAULT_DEPLOYED.router),
  };

  const pasAmount = process.env.INIT_PAS ?? "10000";
  const tokenAmount = process.env.INIT_TOKENDEMO ?? "2000000";

  console.log("Network:", hre.network.name);
  console.log("Deployer:", deployer.address);
  console.log("WETH9:", deployed.weth);
  console.log("Factory:", deployed.factory);
  console.log("Router02:", deployed.router);

  const TokenDemo = await hre.ethers.getContractFactory("TokenDemo");
  const totalSupply = hre.ethers.parseUnits("1000000000", 18);
  const token = await TokenDemo.deploy("TokenDemo", "TokenDemo", 18, totalSupply);
  await token.waitForDeployment();
  console.log("TokenDemo:", token.target);

  const Router = await hre.ethers.getContractFactory("UniswapV2Router02");
  const router = Router.attach(deployed.router);

  const Factory = await hre.ethers.getContractFactory("UniswapV2Factory");
  const factory = Factory.attach(deployed.factory);

  const deadline = (await hre.ethers.provider.getBlock("latest")).timestamp + 3600;

  const tokenDesired = hre.ethers.parseUnits(tokenAmount, 18);
  const value = hre.ethers.parseEther(pasAmount);

  let tx = await token.approve(router.target, tokenDesired);
  console.log("approve TokenDemo->router tx:", tx.hash);
  await tx.wait();

  tx = await router.addLiquidityETH(
    token.target,
    tokenDesired,
    0,
    0,
    deployer.address,
    deadline,
    { value }
  );
  console.log("addLiquidityETH tx:", tx.hash);
  await tx.wait();

  const pair = await factory.getPair(deployed.weth, token.target);
  console.log("Pair (WETH/TokenDemo):", pair);

  console.log("\nExport for agent-backend/env:");
  console.log("AGENT_BACKEND_TOKENDEMO=", token.target);
  console.log("AGENT_BACKEND_UNISWAP_V2_ROUTER=", deployed.router);
  console.log("AGENT_BACKEND_UNISWAP_V2_FACTORY=", deployed.factory);
  console.log("AGENT_BACKEND_WETH9=", deployed.weth);
  console.log("AGENT_BACKEND_DEFAULT_PAIR=", pair);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
