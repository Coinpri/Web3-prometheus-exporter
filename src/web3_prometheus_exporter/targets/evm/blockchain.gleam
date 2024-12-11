import eth_crypto/eth.{type Address, type SmartContract}
import glaml
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import snag.{type Result}
import web3_prometheus_exporter/targets/evm/account
import web3_prometheus_exporter/util/glaml as glaml_util

import web3_prometheus_exporter/targets/evm/asset.{type Asset}

pub opaque type Builder {
  Builder(blockchain_name: String, rpc_url: Uri, assets: Dict(String, Asset))
}

pub type Message {
  QueryBalance(
    asset_id: String,
    account_id: String,
    caller_subject: Subject(Result(Int)),
  )
}

pub fn to_actor(builder: Builder) -> actor.Spec(Nil, Message) {
  actor.Spec(
    init: fn() { actor.Ready(Nil, process.new_selector()) },
    // todo: self-register to chip registry on init
    init_timeout: 10,
    loop: fn(msg: Message, _state: Nil) {
      case msg {
        QueryBalance(asset_id, account_id, caller_subject) -> {
          let ret = {
            use asset <- result.try(get_asset(builder, asset_id))
            use account <- result.try(asset.get_account(asset, account_id))
            let address = account.get_address(account)
            case asset {
              asset.ERC20(_, asset_contract) -> {
                use rpc_response <- result.try(get_balance_from_contract_asset(
                  builder.rpc_url,
                  asset_contract,
                  address,
                ))
                parse_erc20_response(rpc_response)
              }
              asset.ERC721(_, asset_contract) -> {
                use rpc_response <- result.try(get_balance_from_contract_asset(
                  builder.rpc_url,
                  asset_contract,
                  address,
                ))
                parse_erc721_response(rpc_response)
              }
              asset.Native(_) -> eth.eth_get_balance(builder.rpc_url, address)
            }
          }
          process.send(caller_subject, ret)
        }
      }
      actor.continue(Nil)
    },
  )
}

fn get_balance_from_contract_asset(
  rpc_url: Uri,
  asset_contract: asset.AssetSmartContract(any),
  address: Address,
) -> Result(eth.RpcResponse) {
  // Grab contract and selector
  let contract = asset.get_smart_contract(asset_contract)
  let assert Ok(function_selector) = eth.get_function(contract, "balanceOf")

  // call the RPC
  eth.eth_call(
    contract,
    function_selector,
    eth.address_to_bit_array(address),
    rpc_url,
  )
}

fn parse_erc20_response(response: eth.RpcResponse) -> Result(Int) {
  case response {
    eth.RpcError(code, message) ->
      snag.error(
        "rpc error: code: "
        <> int.to_string(code)
        <> " | message: \""
        <> message
        <> "\"",
      )
    eth.RpcResult(result) -> {
      use value <- result.try(
        int.base_parse(string.drop_start(result, 2), 16)
        |> result.try_recover(fn(_) {
          snag.error("result is not valid hexadecimal")
        }),
      )
      Ok(value)
    }
  }
}

fn parse_erc721_response(response: eth.RpcResponse) -> Result(Int) {
  case response {
    eth.RpcError(code, message) ->
      snag.error(
        "rpc error: code: "
        <> int.to_string(code)
        <> " | message: \""
        <> message
        <> "\"",
      )
    eth.RpcResult(result) -> {
      use value <- result.try(
        int.base_parse(string.drop_start(result, 2), 16)
        |> result.try_recover(fn(_) {
          snag.error("result is not valid hexadecimal")
        }),
      )
      Ok(value)
    }
  }
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

// fn query_smart_contract(
//   blockchain_subject: Subject(Message),
//   contract: SmartContract,
//   function_name: String,
//   data: BitArray,
// ) -> Result(Int) {
//   let subject: Subject(Result(String)) = process.new_subject()
//   process.send(
//     blockchain_subject,
//     ViewCallContract(contract, function_name, data, subject),
//   )
//   use result <- result.try(
//     process.receive(subject, 10_000)
//     |> result.try_recover(fn(_) {
//       snag.error("blockchain subject failed to respond")
//     }),
//   )
//   use r <- result.try(result)
//   let assert Ok(balance) = int.base_parse(r, 16)
//   Ok(balance)
// }

pub fn add_asset(
  builder builder: Builder,
  asset asset: Asset,
  asset_id id: String,
) -> Builder {
  Builder(..builder, assets: dict.insert(builder.assets, id, asset))
}

pub fn get_asset(
  builder builder: Builder,
  asset_id asset_id: String,
) -> Result(Asset) {
  dict.get(builder.assets, asset_id)
  |> result.try_recover(fn(_) {
    snag.error("failed to find asset " <> asset_id)
  })
}
