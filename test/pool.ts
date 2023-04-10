import { Calibrator__factory } from "~/typechain/factories/Calibrator__factory"
import { CalibratorProxy__factory } from "~/typechain"
import Big from "big.js"
import { ethers } from "hardhat"
import {
  BigNumber,
  BigNumberish,
  Signer,
} from "ethers"
import { ERC20PresetFixedSupply } from "~/typechain/ERC20PresetFixedSupply"
import { ERC20PresetFixedSupply__factory } from "~/typechain/factories/ERC20PresetFixedSupply__factory"
import { OGXFactory } from "~/typechain/OGXFactory"
import { OGXPair } from "~/typechain/OGXPair"
import { OGXRouter02 } from "~/typechain/OGXRouter02"

import { WrappedNative } from "~/typechain/WrappedNative"
import { WrappedNative__factory } from "~/typechain/factories/WrappedNative__factory"

const OGXRouter02Json = require('../contracts/ogx/precompiled/OGXRouter02.json');
const OGXFactoryJson = require('../contracts/ogx/precompiled/OGXFactory.json');

export const mapValue = (x: BigNumberish) =>
  new Big(x.toString()).div(1e18).toNumber()

export const defaultUniDeadline = () => 9999999999999

export async function buildPool(
  wallet: any,
  feeGetter: string,
  weth: WrappedNative,
  baseToken: ERC20PresetFixedSupply,
  quoteToken: ERC20PresetFixedSupply,
  baseTokenLiq: BigNumber,
  quoteTokenLiq: BigNumber
) {
  const factoryFactory = (await ethers.getContractFactory(
    OGXFactoryJson.abi,
    OGXFactoryJson.bytecode
  ))
  const factory = await factoryFactory.connect(wallet).deploy(wallet.address) as OGXFactory

  await factory.setFeeTo(feeGetter)

  const routerFactory = (await ethers.getContractFactory(
    OGXRouter02Json.abi,
    OGXRouter02Json.bytecode
  ))
  const router = await routerFactory.deploy(factory.address, weth.address) as OGXRouter02

  const createPairResult = await factory.createPair(
    baseToken.address,
    quoteToken.address
  )
  const pairAddress = await factory.getPair(
    baseToken.address,
    quoteToken.address
  )

  const pairFactory = await ethers.getContractFactory("OGXPair")
  const pair = pairFactory.attach(pairAddress) as OGXPair

  const result = await pair.price0CumulativeLast()
  console.log({ result })

  // let liquidityGTON = baseTokenLiq
  // let liquidityWETH = quoteTokenLiq
  await baseToken.connect(wallet).approve(router.address, baseTokenLiq)
  await quoteToken.connect(wallet).approve(router.address, quoteTokenLiq)

  let block = await wallet.provider.getBlock("latest")
  let timestamp = block.timestamp

  // console.log("addliq", [
  //   baseToken.address,
  //   quoteToken.address,
  //   baseTokenLiq,
  //   quoteTokenLiq,
  //   1,
  //   1,
  //   wallet.address,
  //   timestamp + 3600,
  // ])

  await router
    .connect(wallet)
    .addLiquidity(
      baseToken.address,
      quoteToken.address,
      baseTokenLiq,
      quoteTokenLiq,
      1,
      1,
      wallet.address,
      timestamp + 3600
    )

  // await expect(
  //   router.addLiquidity(
  //     baseToken.address,
  //     quoteToken.address,
  //     baseTokenLiq,
  //     quoteTokenLiq,
  //     1,
  //     1,
  //     wallet.address,
  //     timestamp + 3600
  //   )
  // )
  // .to.emit(pair, "Sync")
  // .withArgs(baseTokenLiq.toString(), quoteTokenLiq.toString())
  // .to.emit(pair, "Mint")
  // .withArgs(router.address, baseTokenLiq.toString(), quoteTokenLiq.toString())

  // expect(await pair.token1()).to.eq(baseToken.address)
  // expect(await pair.token0()).to.eq(quoteToken.address)

  const lpOwnerHoldings = await pair.balanceOf(wallet.address)

  return { pair, factory, router, lpOwnerHoldings }
}

export const deployTokenFixedSupply = async (
  name: string,
  symbol: string,
  initialSupply: BigNumberish,
  owner: string
): Promise<ERC20PresetFixedSupply> => {
  const tokenFactory = (await ethers.getContractFactory(
    "ERC20PresetFixedSupply"
  )) as ERC20PresetFixedSupply__factory

  const token = await tokenFactory.deploy(name, symbol, initialSupply, owner)

  return token
}

export type CalibrateToken = {
  name: string
  symbol: string
}
export type CalibrateInput = {
  mintA: string
  mintB: string
  liqA: string
  liqB: string
  base: CalibrateToken
  quote: CalibrateToken
  targetPrice: number

  // (x: Big) => x.div(10)
  removalFn: (x: Big) => Big
}

export enum CalibrateDirection {
  Up,
  Down,
}

export type ProxyCalibrateInput = {
  mintA: string
  mintB: string
  liqA: string
  liqB: string
  base: CalibrateToken
  quote: CalibrateToken
  direction: CalibrateDirection
  // percentageOfLPs: { n: number; d: number } // 0 to 1
  deployer: Signer
  feeGetter: string
}

export async function prepareTokensAndPoolsForProxy(cfg: ProxyCalibrateInput) {
  const baseToken = await deployTokenFixedSupply(
    cfg.base.name,
    cfg.base.symbol,
    cfg.mintA,
    await cfg.deployer.getAddress()
  )
  const quoteToken = await deployTokenFixedSupply(
    cfg.quote.name,
    cfg.quote.symbol,
    cfg.mintB,
    await cfg.deployer.getAddress()
  )

  const wethFactory = (await ethers.getContractFactory(
    "WrappedNative"
  )) as WrappedNative__factory

  const weth = await wethFactory.deploy()

  const builtPoolResponse = await buildPool(
    cfg.deployer,
    cfg.feeGetter,
    weth,
    baseToken,
    quoteToken,
    BigNumber.from(cfg.liqA),
    BigNumber.from(cfg.liqB)
  )
  const { router } = builtPoolResponse

  const calibratorFactory = (await ethers.getContractFactory(
    "Calibrator"
  )) as Calibrator__factory

  const calibrator = await calibratorFactory.deploy(
    baseToken.address,
    router.address,
    "QUICK"
  )

  const calibratorProxyFactory = (await ethers.getContractFactory(
    "CalibratorProxy"
  )) as CalibratorProxy__factory

  const calibratorProxy = await calibratorProxyFactory.deploy(
    calibrator.address,
    baseToken.address
  )

  return {
    calibratorProxy,
    calibrator,
    builtPoolResponse,
    baseToken,
    quoteToken,
  }
}

export function inferPrice(a: number, b: number, target: number) {
  const a_c = -1 * target
  const b_c = -1 * b + a * target

  const d = Math.pow(b_c, 2) - 4 * a_c * 0

  const x1 = (-b_c - Math.sqrt(d)) / (2 * a_c)
  const x2 = (-b_c + Math.sqrt(d)) / (2 * a_c)

  const r = x1 === 0 ? x2 : x1

  console.log({ r, d })

  return r
}
