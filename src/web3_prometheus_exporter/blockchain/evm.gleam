import glaml
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import gleam/uri.{type Uri}
import snag.{type Result}

import web3_prometheus_exporter/util/glaml as glaml_util

import eth_crypto/eth.{type Address, type SmartContract}
import eth_crypto/standards/erc20
import eth_crypto/standards/erc721

pub type Message(id) {
  QueryNativeBalance(address: eth.Address, subject: Subject(Int))
  ViewCallContract(
    contract_id: id,
    function_name: String,
    data: String,
    subject: Subject(String),
  )
}

pub opaque type Builder(account_id) {
  Builder(
    blockchain_name: String,
    rpc_url: Uri,
    accounts: Dict(account_id, Account),
  )
}

pub opaque type Account {
  Account(account_name: String, asset: Asset, address: Address)
}

pub opaque type Asset {
  Native
  ERC20(contract: SmartContract(String))
  ERC721(contract: SmartContract(String))
}

pub fn new(blockchain_name: String, rpc_url: Uri) -> Builder(id) {
  Builder(blockchain_name, rpc_url, dict.new())
}

pub fn from_yaml(node: glaml.DocNode) -> Result(Builder(id)) {
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
  Ok(Builder(name, rpc_url, dict.new()))
}

pub fn to_actor(builder: Builder(id)) -> actor.Spec(Nil, Message(id)) {
  actor.Spec(
    init: fn() { actor.Ready(Nil, process.new_selector()) },
    init_timeout: 10,
    loop: fn(msg: Message(id), _state: Nil) {
      case msg {
        QueryNativeBalance(_address, subject) -> process.send(subject, 69_420)
        ViewCallContract(_contract_id, _function_name, _data, subject) ->
          process.send(subject, "Hi from " <> builder.blockchain_name)
      }
      actor.continue(Nil)
    },
  )
}

pub fn add_account(
  builder: Builder(id),
  id: id,
  account: Account,
) -> Builder(id) {
  Builder(..builder, accounts: dict.insert(builder.accounts, id, account))
}

pub fn new_account(
  name: String,
  asset: Asset,
  address: String,
) -> Result(Account) {
  use addr <- result.try(eth.address_from_string(address))
  Ok(Account(name, asset, addr))
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
