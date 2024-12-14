import eth_crypto/eth.{type Address}
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import snag.{type Result}
import web3_prometheus_exporter/targets/evm/account

import web3_prometheus_exporter/blockchain.{
  type Message, GetAccounts, GetAssets, QueryBalance,
}
import web3_prometheus_exporter/targets/evm/asset.{type Asset}

/// Builder pattern. Use the builder to create a blockchain actor
/// with `to_actor`
pub opaque type Builder {
  Builder(rpc_url: Uri, assets: Dict(String, Asset))
}

/// Return a new blockchain actor Builder
pub fn new(rpc_url rpc_url: Uri) -> Builder {
  Builder(rpc_url, dict.new())
}

/// Add a single asset to the Builder
pub fn add_asset(
  builder builder: Builder,
  asset asset: Asset,
  asset_id id: String,
) -> Builder {
  Builder(..builder, assets: dict.insert(builder.assets, id, asset))
}

/// Fetch an asset with given asset id from the Builder
pub fn get_asset(
  builder builder: Builder,
  asset_id asset_id: String,
) -> Result(Asset) {
  dict.get(builder.assets, asset_id)
  |> result.try_recover(fn(_) {
    snag.error("failed to find asset " <> asset_id)
  })
}

/// Add multiple assets.
/// Overlapping asset ids will be overwritten
pub fn add_assets(
  builder builder: Builder,
  assets assets: Dict(String, Asset),
) -> Builder {
  Builder(
    ..builder,
    assets: dict.combine(builder.assets, assets, fn(_, new) { new }),
  )
}

/// Turn a BUilder into an actor spec that can be used
/// with `blockchain.actor_to_child_builder`
pub fn to_actor(builder: Builder) -> actor.Spec(Nil, Message) {
  actor.Spec(
    init: fn() {
      process.self()
      actor.Ready(Nil, process.new_selector())
    },
    init_timeout: 10,
    loop: fn(msg: Message, _state: Nil) {
      case msg {
        QueryBalance(asset_id, account_id, caller_subject) ->
          process.send(
            caller_subject,
            handle_query_balance(builder, asset_id, account_id),
          )
        GetAssets(caller_subject) ->
          process.send(caller_subject, handle_get_assets(builder))
        GetAccounts(asset_id, caller_subject) ->
          process.send(caller_subject, handle_get_accounts(builder, asset_id))
      }
      actor.continue(Nil)
    },
  )
}

/// `eth_call` the `balanceOf` function of either a ERC20 or ERC721 contract.
/// Panics if the provided contract does not have a function labelled "balanceOf"
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

/// To use on the return value from `get_balance_from_contract_asset`
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

/// To use on the return value from `get_balance_from_contract_asset`
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

fn handle_query_balance(
  builder: Builder,
  asset_id: String,
  account_id: String,
) -> Result(Int) {
  use asset <- result.try(get_asset(builder, asset_id))
  use account <- result.try(asset.get_account(asset, account_id))
  let address = account.get_address(account)
  case asset {
    asset.ERC20(_, _, _, asset_contract) -> {
      use rpc_response <- result.try(get_balance_from_contract_asset(
        builder.rpc_url,
        asset_contract,
        address,
      ))
      parse_erc20_response(rpc_response)
    }
    asset.ERC721(_, _, _, asset_contract) -> {
      use rpc_response <- result.try(get_balance_from_contract_asset(
        builder.rpc_url,
        asset_contract,
        address,
      ))
      parse_erc721_response(rpc_response)
    }
    asset.Native(_, _, _) -> eth.eth_get_balance(builder.rpc_url, address)
  }
}

fn handle_get_assets(builder: Builder) -> List(blockchain.Asset) {
  dict.fold(builder.assets, [], fn(assets, id, asset) {
    let #(kind, details, interval, timeout) = case asset {
      asset.ERC20(_, interval, timeout, contract) -> #(
        "ERC20",
        dict.from_list([
          #(
            "contract address",
            contract
              |> asset.get_smart_contract
              |> eth.get_contract_address
              |> eth.address_to_string,
          ),
        ]),
        interval,
        timeout,
      )
      asset.ERC721(_, interval, timeout, contract) -> #(
        "ERC721",
        dict.from_list([
          #(
            "contract address",
            contract
              |> asset.get_smart_contract
              |> eth.get_contract_address
              |> eth.address_to_string,
          ),
        ]),
        interval,
        timeout,
      )
      asset.Native(_, interval, timeout) -> #(
        "Native",
        dict.new(),
        interval,
        timeout,
      )
    }
    [blockchain.Asset(id, kind, details, interval, timeout), ..assets]
  })
}

fn handle_get_accounts(
  builder: Builder,
  asset_id: String,
) -> Result(List(blockchain.Account)) {
  use asset <- result.map(
    dict.get(builder.assets, asset_id)
    |> result.try_recover(fn(_) {
      snag.error("did not find asset id " <> asset_id)
    }),
  )
  dict.fold(asset.accounts, [], fn(accounts, account_id, account) {
    [
      blockchain.Account(
        account_id,
        account.get_address(account) |> eth.address_to_string,
        dict.new(),
        account.get_interval(account),
        account.get_timeout(account),
      ),
      ..accounts
    ]
  })
}
