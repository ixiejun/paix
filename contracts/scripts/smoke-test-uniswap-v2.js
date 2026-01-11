const hre = require("hardhat");

const DEPLOYED = {
  weth: "0x4042196503b0C1E1f4188277bFfA46373FCf3576",
  factory: "0xdCB1Bc3F7b806E553FC79E48768c809c051734Ef",
  router: "0x9aeAf6995b64A490fe1c2a8c06Dc2E912a487710"
};

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0];
  const user = signers[1] || deployer;

  console.log("Network:", hre.network.name);
  console.log("Deployer:", deployer.address);
  console.log("User:", user.address);
  console.log("Router02:", DEPLOYED.router);
  console.log("Factory:", DEPLOYED.factory);
  console.log("WETH9:", DEPLOYED.weth);

  const Router = await hre.ethers.getContractFactory("UniswapV2Router02");
  const router = Router.attach(DEPLOYED.router);

  const Factory = await hre.ethers.getContractFactory("UniswapV2Factory");
  const factory = Factory.attach(DEPLOYED.factory);

  const TestERC20 = await hre.ethers.getContractFactory("TestERC20");
  const tokenA = await TestERC20.deploy("SmokeTokenA", "sTKA", hre.ethers.parseUnits("1000000", 18));
  await tokenA.waitForDeployment();
  const tokenB = await TestERC20.deploy("SmokeTokenB", "sTKB", hre.ethers.parseUnits("1000000", 18));
  await tokenB.waitForDeployment();

  console.log("TokenA:", tokenA.target);
  console.log("TokenB:", tokenB.target);

  const deadline = (await hre.ethers.provider.getBlock("latest")).timestamp + 3600;

  // Create pair (idempotent)
  const existingPair = await factory.getPair(tokenA.target, tokenB.target);
  if (existingPair === hre.ethers.ZeroAddress) {
    const tx = await factory.createPair(tokenA.target, tokenB.target);
    console.log("createPair tx:", tx.hash);
    await tx.wait();
  } else {
    console.log("Pair already exists:", existingPair);
  }

  const pairAddress = await factory.getPair(tokenA.target, tokenB.target);
  console.log("Pair:", pairAddress);

  // Add liquidity
  const amountA = hre.ethers.parseUnits("1000", 18);
  const amountB = hre.ethers.parseUnits("1000", 18);

  let tx = await tokenA.approve(router.target, amountA);
  await tx.wait();
  tx = await tokenB.approve(router.target, amountB);
  await tx.wait();

  tx = await router.addLiquidity(
    tokenA.target,
    tokenB.target,
    amountA,
    amountB,
    0,
    0,
    deployer.address,
    deadline
  );
  console.log("addLiquidity tx:", tx.hash);
  await tx.wait();

  // Swap exact tokens for tokens
  const swapIn = hre.ethers.parseUnits("10", 18);
  if (user.address !== deployer.address) {
    tx = await tokenA.transfer(user.address, swapIn);
    await tx.wait();
  }

  tx = await tokenA.connect(user).approve(router.target, swapIn);
  await tx.wait();

  const outBefore = await tokenB.balanceOf(user.address);
  tx = await router.connect(user).swapExactTokensForTokens(
    swapIn,
    0,
    [tokenA.target, tokenB.target],
    user.address,
    deadline
  );
  console.log("swapExactTokensForTokens tx:", tx.hash);
  await tx.wait();

  const outAfter = await tokenB.balanceOf(user.address);
  console.log("User TokenB outBefore:", outBefore.toString());
  console.log("User TokenB outAfter:", outAfter.toString());

  if (outAfter <= outBefore) {
    throw new Error("Smoke test failed: swap output did not increase");
  }

  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
