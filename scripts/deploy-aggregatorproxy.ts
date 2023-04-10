import { EACAggregatorProxy__factory } from "~/typechain"

import { ethers } from "hardhat"

async function mn() {
  const [wallet] = await ethers.getSigners()

  const factory = (await ethers.getContractFactory(
    "EACAggregatorProxy"
  )) as EACAggregatorProxy__factory

  const pworacle = "0x548A2b214493290bB45D516f16176Be01dbf1674"
  const accessController = pworacle
  const resp = await factory.connect(wallet).deploy(pworacle, accessController)

  await resp.deployed()
  // console.log({ resp: tx })
}

mn()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
