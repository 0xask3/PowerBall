import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { abi as TokenAbi } from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { abi as RouterAbi } from "@uniswap/v2-periphery/build/IUniswapV2Router02.json";
import { BigNumber } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";

task("addLiquidity", "Adds liquidity to a specific token")
  .addParam("token", "Address of token contract")
  .addParam("router", "Address of router")
  .setAction(async function (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) {
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();
    const Router = await new hre.ethers.Contract(taskArguments.router, RouterAbi, signers[0]);
    const Token = await new hre.ethers.Contract(taskArguments.token, TokenAbi, signers[0]);

    const supply: string = BigInt((await Token.totalSupply()) / 2).toString();
    const ethAmount: string = (1e16).toString();
    console.log("\nApproving token...\n");
    let tx = await Token.approve(Router.address, supply);
    await tx.wait(3);
    console.log("Approved succesfully\n");

    console.log("Adding liquidity...\n");
    tx = await Router.addLiquidityETH(Token.address, supply, 0, 0, Router.address, 1e10, { value: ethAmount });
    await tx.wait(3);
    console.log("Liquidity added succesfully");
  });
