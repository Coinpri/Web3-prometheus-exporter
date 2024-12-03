import glaml
import gleam/result
import gleam/uri.{type Uri}
import snag.{type Result}

import web3_prometheus_exporter/util/glaml as glaml_util

import eth_crypto/eth.{type Address, type SmartContract}
import eth_crypto/standards/erc20
import eth_crypto/standards/erc721

pub opaque type Builder {
  Builder(name: String, rpc_url: Uri, accounts: List(Account))
}

pub opaque type Account {
  Account(asset: Asset, address: Address)
}

pub opaque type Asset {
  Native
  ERC20(contract: SmartContract)
  ERC721(contract: SmartContract)
}

pub fn from_yaml(node: glaml.DocNode) -> Result(Builder) {
  use name_node <- result.try(
    glaml.sugar(node, "name")
    |> result.try_recover(fn(_) {
      snag.error("could not find yaml node \"name\"")
    }),
  )
  use rpc_url_node <- result.try(
    glaml.sugar(node, "rpc_url")
    |> result.try_recover(fn(_) {
      snag.error("could not find yaml node \"rpc_url\"")
    }),
  )

  use name <- result.try(glaml_util.glaml_node_to_string(name_node))
  use rpc_url_string <- result.try(glaml_util.glaml_node_to_string(rpc_url_node))

  use rpc_url <- result.try(
    uri.parse(rpc_url_string)
    |> result.try_recover(fn(_) { snag.error("rpc url could not be parsed") }),
  )
  Ok(Builder(name, rpc_url, []))
}

pub fn new(name: String, rpc_url: Uri) -> Builder {
  Builder(name, rpc_url, [])
}

pub fn add_account(evm_mon: Builder, account: Account) -> Builder {
  Builder(..evm_mon, accounts: [account, ..evm_mon.accounts])
}

pub fn new_account(asset: Asset, address: String) -> Result(Account) {
  use addr <- result.try(eth.address_from_string(address))
  Ok(Account(asset, addr))
}

pub fn new_native_asset() -> Asset {
  Native
}

pub fn new_erc20_asset(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc20.new(addr)
  ERC20(contract)
}

pub fn new_erc721_asset(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc721.new(addr)
  ERC721(contract)
}
