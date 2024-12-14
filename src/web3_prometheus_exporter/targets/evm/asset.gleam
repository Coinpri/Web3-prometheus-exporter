import eth_crypto/eth.{type SmartContract}
import eth_crypto/standards/erc20
import eth_crypto/standards/erc721
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/result
import snag.{type Result}

import web3_prometheus_exporter/targets/evm/account.{type Account}

/// EVM-specific token assets.
/// Native = Ether for Ethereum, Matic for Polygon etc
/// ERC20 = Smart contract following the ERC20 standard (simple token)
/// ERC721 = Smart contract following the ERC721 standard (NFT)
pub type Asset {
  Native(
    accounts: Dict(String, Account),
    timeout: Option(Int),
    interval: Option(Int),
  )
  ERC20(
    accounts: Dict(String, Account),
    timeout: Option(Int),
    interval: Option(Int),
    contract: AssetSmartContract(ERC20),
  )
  ERC721(
    accounts: Dict(String, Account),
    timeout: Option(Int),
    interval: Option(Int),
    contract: AssetSmartContract(ERC721),
  )
}

/// Differenciating smart contract standards with a phantom type.
pub opaque type AssetSmartContract(kind) {
  AssetSmartContract(contract: SmartContract)
}

/// AssetSmartContract phantom types
pub type ERC20

pub type ERC721

/// Add a single account to the asset
pub fn add_account(
  asset asset: Asset,
  account account: Account,
  id id: String,
) -> Asset {
  dict.insert(asset.accounts, id, account)
  |> {
    case asset {
      ERC20(_, interval, timeout, contract) -> ERC20(
        _,
        interval,
        timeout,
        contract,
      )
      ERC721(_, interval, timeout, contract) -> ERC721(
        _,
        interval,
        timeout,
        contract,
      )
      Native(_, interval, timeout) -> Native(_, interval, timeout)
    }
  }
}

/// Add multiple accounts to the asset.
/// Overlapping account ids will be overwritten
pub fn add_accounts(
  asset asset: Asset,
  accounts accounts: Dict(String, Account),
) -> Asset {
  dict.combine(asset.accounts, accounts, fn(_, new) { new })
  |> {
    case asset {
      ERC20(_, interval, timeout, contract) -> ERC20(
        _,
        interval,
        timeout,
        contract,
      )
      ERC721(_, interval, timeout, contract) -> ERC721(
        _,
        interval,
        timeout,
        contract,
      )
      Native(_, interval, timeout) -> Native(_, interval, timeout)
    }
  }
}

/// Create a new native asset
pub fn new_native() -> Asset {
  Native(dict.new(), None, None)
}

/// Create a new ERC20 asset from the ERC20 smart contract address.
/// Note that while the address format will be validated,
/// whether it points to a valid erc20 contract won't be.
pub fn new_erc20(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc20.new(addr)
  ERC20(dict.new(), None, None, AssetSmartContract(contract))
}

/// Create a new ERC721 asset from the ERC721 smart contract address.
/// Note that while the address format will be validated,
/// whether it points to a valid erc20 contract won't be.
pub fn new_erc721(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc721.new(addr)
  ERC721(dict.new(), None, None, AssetSmartContract(contract))
}

/// Return the actionnable smart contract (defined in Gleam_EVM)
/// from the `AssetSmartContract` wrapper.
pub fn get_smart_contract(
  contract contract: AssetSmartContract(any),
) -> SmartContract {
  contract.contract
}

/// Try to fetch the account from a given id
pub fn get_account(
  asset asset: Asset,
  account_id account_id: String,
) -> Result(Account) {
  dict.get(asset.accounts, account_id)
  |> result.try_recover(fn(_) {
    snag.error("failed to find account " <> account_id)
  })
}

/// Set asset-level timeout
pub fn set_timeout(asset asset: Asset, timeout timeout: Option(Int)) -> Asset {
  let new_timeout = case timeout {
    None -> None
    Some(timeout_ms) if timeout_ms > 0 -> Some(timeout_ms)
    Some(_) -> asset.timeout
  }

  case asset {
    ERC20(accounts, interval, _, contract) ->
      ERC20(accounts, interval, new_timeout, contract)
    ERC721(accounts, interval, _, contract) ->
      ERC721(accounts, interval, new_timeout, contract)
    Native(accounts, interval, _) -> Native(accounts, interval, new_timeout)
  }
}

/// Set asset-level interval
pub fn set_interval(asset asset: Asset, interval interval: Option(Int)) -> Asset {
  let new_interval = case interval {
    None -> None
    Some(interval_ms) if interval_ms > 0 -> Some(interval_ms)
    Some(_) -> asset.timeout
  }
  case asset {
    ERC20(accounts, _, timeout, contract) ->
      ERC20(accounts, new_interval, timeout, contract)
    ERC721(accounts, _, timeout, contract) ->
      ERC721(accounts, new_interval, timeout, contract)
    Native(accounts, _, timeout) -> Native(accounts, new_interval, timeout)
  }
}
