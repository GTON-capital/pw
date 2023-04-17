import { ethers } from "hardhat"
import { BigNumberish } from "ethers"

import { PWPegger, PWPegger__factory } from "~/typechain"

export type PWPeggerConfig = {
  admin: string
  keeper: string
  calibratorProxy: string
  vault: string
  pool: string
  quoteToken: string
  emergencyth: BigNumberish
  volatilityth: BigNumberish
  frontrunth: BigNumberish
  decimals: BigNumberish
}

export async function preparePWPeggerEnvironment(
  pwPeggerCfg: PWPeggerConfig
): Promise<PWPeggerContext> {
  const [wallet] = await ethers.getSigners()

  const pwPeggerFactory = (await await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory
  const pwPeggerContract = await pwPeggerFactory
    .connect(wallet)
    .deploy(pwPeggerCfg)

  return {
    pwPeggerContract,
  }
}

export type PWPeggerContext = {
  pwPeggerContract: PWPegger
}

export type PWPeggerContextExtended<T> = T & PWPeggerContext

export async function preparePWPeggerWithEACAggregatorProxy(): Promise<PWPeggerContextExtended<{
}> | null> {
  return null
}
