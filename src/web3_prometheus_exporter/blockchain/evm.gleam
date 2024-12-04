import glaml
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import snag.{type Result}

import web3_prometheus_exporter/util/glaml as glaml_util

import eth_crypto/eth.{type Address, type SmartContract}
import eth_crypto/standards/erc20
import eth_crypto/standards/erc721

pub type Message {
  QueryNativeBalance(address: eth.Address, subject: Subject(Result(Int)))
  ViewCallContract(
    contract: SmartContract,
    function_name: String,
    data: BitArray,
    subject: Subject(Result(String)),
  )
}

pub opaque type AccountMessage {
  QueryBalance(subject: Subject(Int))
  GetAccount(subject: Subject(Account))
}

pub opaque type Builder {
  Builder(blockchain_name: String, rpc_url: Uri, assets: Dict(String, Asset))
}

type Account {
  Account(address: Address)
}

pub opaque type Asset {
  Native(accounts: Dict(String, Account))
  ERC20(accounts: Dict(String, Account), contract: SmartContract)
  ERC721(accounts: Dict(String, Account), contract: SmartContract)
}

pub fn new(
  blockchain_name blockchain_name: String,
  rpc_url rpc_url: Uri,
) -> Builder {
  Builder(blockchain_name, rpc_url, dict.new())
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
  Ok(Builder(name, rpc_url, dict.new()))
}

pub fn to_actors(
  builder: Builder,
) -> #(actor.Spec(Nil, Message), Dict(String, actor.Spec(Nil, AccountMessage))) {
  let blockchain_actor =
    actor.Spec(
      init: fn() { actor.Ready(Nil, process.new_selector()) },
      init_timeout: 10,
      loop: fn(msg: Message, _state: Nil) {
        case msg {
          QueryNativeBalance(_address, subject) ->
            process.send(subject, Ok(69_420))
          ViewCallContract(contract, function_name, data, subject) -> {
            let assert Ok(function) = eth.get_function(contract, function_name)
            let response =
              eth.eth_call(contract, function, data, builder.rpc_url)
            process.send(subject, response)
          }
        }
        actor.continue(Nil)
      },
    )
  let accounts_actors = todo
  #(blockchain_actor, accounts_actors)
}

fn query_smart_contract(
  blockchain_subject: Subject(Message),
  contract: SmartContract,
  function_name: String,
  data: BitArray,
) -> Result(Int) {
  let subject: Subject(Result(String)) = process.new_subject()
  process.send(
    blockchain_subject,
    ViewCallContract(contract, function_name, data, subject),
  )
  use result <- result.try(
    process.receive(subject, 10_000)
    |> result.try_recover(fn(_) {
      snag.error("blockchain subject failed to respond")
    }),
  )
  use r <- result.try(result)
  let assert Ok(balance) = int.base_parse(r, 16)
  Ok(balance)
}

pub fn add_asset(
  builder builder: Builder,
  asset_name name: String,
  asset asset: Asset,
) -> Builder {
  Builder(..builder, assets: dict.insert(builder.assets, name, asset))
}

pub fn add_account(
  asset asset: Asset,
  id id: String,
  address address: Address,
) -> Asset {
  case asset {
    ERC20(accounts, contract) ->
      ERC20(dict.insert(accounts, id, Account(address)), contract)
    ERC721(accounts, contract) ->
      ERC721(dict.insert(accounts, id, Account(address)), contract)
    Native(accounts) -> Native(dict.insert(accounts, id, Account(address)))
  }
}

pub fn new_native_asset() -> Asset {
  Native(dict.new())
}

pub fn new_erc20_asset(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc20.new(addr)
  ERC20(dict.new(), contract)
}

pub fn new_erc721_asset(contract_address at: String) -> Result(Asset) {
  use addr <- result.map(eth.address_from_string(at))
  let contract = erc721.new(addr)
  ERC721(dict.new(), contract)
}
