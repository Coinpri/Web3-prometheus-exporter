import glaml
import gleam/bit_array
import gleam/bool
import gleam/result
import gleam/uri.{type Uri}
import snag.{type Result}

import web3_prometheus_exporter/util/glaml as glaml_util

pub opaque type Builder {
  Builder(name: String, rpc_url: Uri, accounts: List(Account))
}

pub opaque type Account {
  Account(asset: Asset, address: Address)
}

pub type Asset {
  Native
  ERC20(contract: SmartContract)
  ERC721(contract: SmartContract)
}

pub opaque type SmartContract {
  SmartContract(abi: String, address: Address)
}

pub opaque type Address {
  Address(address: String)
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
  use addr <- result.try(address_from_string(address))
  Ok(Account(asset, addr))
}

pub fn new_smart_contract(abi: String, address: String) -> Result(SmartContract) {
  use addr <- result.try(address_from_string(address))
  use <- bool.guard(!is_abi_valid(abi), snag.error("invalid ABI"))
  Ok(SmartContract(abi, addr))
}

pub fn address_from_string(from: String) -> Result(Address) {
  let no_leading_0x = case from {
    "0x" <> rest -> rest
    _ -> from
  }
  use decoded_address <- result.try(
    bit_array.base16_decode(no_leading_0x)
    |> result.try_recover(fn(_) { snag.error("not a valid hex string") }),
  )
  use <- bool.guard(
    bit_array.byte_size(decoded_address) != 20,
    snag.error("address is not 20 bytes long"),
  )

  Ok(Address(from))
}

pub fn is_abi_valid(_abi: String) -> Bool {
  True
  // TODO
}
