import Big from "big.js"
import { ethers } from "hardhat"

import { CalibratorProxy__factory, PWPegger__factory } from "~/typechain"
import { Calibrator__factory } from "~/typechain/factories/Calibrator__factory"
import { PWPeggerConfig } from "~/test/pegger"

async function mutatePWConfig(addr: string, config: PWPeggerConfig) {
  const factory = (await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory

  const pwpegger = factory.attach(addr)

  const r = await pwpegger.updPWConfig(config)
  const resp = await r.wait()

  return resp
}

async function mn() {
  const hre = require("hardhat")

  const [wallet] = await ethers.getSigners()

  const factory = (await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory
  const calibratorFactory = (await ethers.getContractFactory(
    "Calibrator"
  )) as Calibrator__factory
  const calibratorProxyFactory = (await ethers.getContractFactory(
    "CalibratorProxy"
  )) as CalibratorProxy__factory

  const ogxtGTON = "0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2"
  const simTSLAtestnet = "0xBca5De3E6Ea3B39770C0a6EF3793e8fA6424031e"
  const tslaKeeperTestnet = "0x442cD59CaeAa047d58F76057164Cd645E1ecF85f" // Admin wallet that sets prices 
  const simTSLA_pool_gton = "0x45581064DE5264f458C59bbF861BA01142cC5b0b"
  const ogxRouter02testnet = "0xf4503ca35E2a9b781f8a7615Ab1FE67fF6BC4396"
  const simTSLAHolderTestnet = "0xf7a643F3Dfc4b49a06e30AfA349ae13873FF86BD"

  const quoteAsset = simTSLAtestnet
  const baseAsset = ogxtGTON
  const router = ogxRouter02testnet
  const admin = tslaKeeperTestnet
  const keeper = tslaKeeperTestnet
  const currentLPHolder = simTSLAHolderTestnet

  // const calibratorProxy = "0xF3ca94706164ca970B649CE72F7e424ad18cd850"
  const calibrator = await calibratorFactory.deploy(
    baseAsset, // base
    router, // router
    "OGX"
  )

  const calibratorProxy = await calibratorProxyFactory.deploy(
    calibrator.address,
    baseAsset // base
  )

  console.log({
    calibratorProxy: calibratorProxy.address,
    calibrator: calibrator.address,
  })

  // const pwpegbasedon = "0x828761B78E22f5A24240d3EFBA04D1f0b25f4EFE"

  const config: PWPeggerConfig = {
    // admin: string
    admin: admin,
    // keeper: string
    keeper: keeper,
    // calibrator: string
    calibrator: calibratorProxy.address,
    // vault: string
    vault: currentLPHolder,
    // pool: string
    pool: simTSLA_pool_gton,
    // token: string
    token: quoteAsset,
    /*
      uint emergencyth - 10% (0.1 * 10^6)
      uint volatilityth - 3% (0.03 * 10^6)
      uint frontrunth - 2% (0.02 * 10^6);
    */
    // emergencyth: BigNumberish
    emergencyth: new Big(0.5).mul(1e6).toFixed(), //50% th
    volatilityth: new Big(0.05).mul(1e6).toFixed(),
    frontrunth: new Big(0.04).mul(1e6).toFixed(),
    // decimals: BigNumberish
    decimals: 6,
  }

  const response = await factory.connect(wallet).deploy(config)
  // const response = await factory.connect(wallet).deploy(config, {
  //   gasLimit: 5_000_000,
  //   gasPrice: new Big(400).mul(1e9).toNumber(),
  // })
  // const r = await response.deployed()
  console.log({
    config,
    pwpegger: response.address,
    // pwpegger: r.address,
  })

  console.log("verifying...")
  await hre.run("verify:verify", {
    address: response.address,
    constructorArguments: [config],
  })
}

mn()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
