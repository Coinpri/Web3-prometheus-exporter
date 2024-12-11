import eth_crypto/eth.{type SmartContract}
import eth_crypto/standards/erc20
import eth_crypto/standards/erc721
import gleam/dict.{type Dict}
import gleam/result
import snag.{type Result}

import web3_prometheus_exporter/targets/evm/account.{type Account}

pub type Asset {
  Native(accounts: Dict(String, Account))
  ERC20(accounts: Dict(String, Account), contract: AssetSmartContract(ERC20))
  ERC721(accounts: Dict(String, Account), contract: AssetSmartContract(ERC721))
}

pub opaque type AssetSmartContract(kind) {
  AssetSmartContract(contract: SmartContract)
}

pub type ERC20

pub type ERC721

pub fn add_account(
  asset asset: Asset,
  account account: Account,
  id id: String,
) -> Asset {
  dict.insert(asset.accounts, id, account)
  |> {
    case asset {
      ERC20(_, contract) -> ERC20(_, contract)
      ERC721(_, contract) -> ERC721(_, contract)
      Native(_) -> Native(_)
    }
  }
}

pub fn new_native() -> Asset {
  Native(dict.new())
}

pub fn new_erc20(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc20.new(addr)
  ERC20(dict.new(), AssetSmartContract(contract))
}

pub fn new_erc721(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc721.new(addr)
  ERC721(dict.new(), AssetSmartContract(contract))
}

pub fn get_smart_contract(
  contract contract: AssetSmartContract(any),
) -> SmartContract {
  contract.contract
}

pub fn get_account(
  asset asset: Asset,
  account_id account_id: String,
) -> Result(Account) {
  dict.get(asset.accounts, account_id)
  |> result.try_recover(fn(_) {
    snag.error("failed to find account " <> account_id)
  })
}
