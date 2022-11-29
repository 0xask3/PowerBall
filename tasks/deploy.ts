import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";

task("deploy", "Deploys a given contract")
  .addParam("contract", "Name of contract to be deployed")
  .addOptionalParam("args", "Constructor arguments for contract")
  .addFlag("verify", "Whether verify the contract or not")
  .setAction(async function (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) {
    await hre.run("compile");
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();
    const Factory = await hre.ethers.getContractFactory(taskArguments.contract);
    let contract: any, args: any;
    console.log(`\nDeploying contract: ${taskArguments.contract} \n`);

    if (taskArguments.args) {
      const params: String[] = taskArguments.args.split(",");
      contract = await Factory.connect(signers[0]).deploy(...params);
      args = [...params];
    } else {
      contract = await Factory.connect(signers[0]).deploy();
      args = [];
    }

    console.log("Contract deployed, waiting for 3 confirmations...\n");
    await contract.deployTransaction.wait(3);
    console.log(`${taskArguments.contract} deployed to: ${contract.address} \n`);

    if (taskArguments.verify) {
      console.log(`Verifying contract: ${taskArguments.contract} \n`);
      await hre.run("verify:verify", {
        address: contract.address,
        contract: `contracts/${taskArguments.contract}.sol:${taskArguments.contract}`,
        constructorArguments: args,
      });
    }
  });
