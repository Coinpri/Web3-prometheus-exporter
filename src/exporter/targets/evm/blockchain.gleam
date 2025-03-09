import eth_crypto/eth.{type Address}
import exporter/prometheus
import exporter/targets/evm/account
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import snag.{type Result}

import exporter/blockchain.{type Message, GetAccounts, GetAssets, QueryBalance}
import exporter/targets/evm/asset.{type Asset}

const default_native_decimals = 18

/// Builder pattern. Use the builder to create a blockchain actor
/// with `to_actor`
pub opaque type Builder {
  Builder(blockchain_id: String, rpc_url: Uri, assets: Dict(String, Asset))
}

/// Return a new blockchain actor Builder
pub fn new(blockchain_id blockchain_id: String, rpc_url rpc_url: Uri) -> Builder {
  Builder(blockchain_id, rpc_url, dict.new())
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
  |> result.replace_error(snag.new("failed to find asset " <> asset_id))
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
    init: fn() { actor.Ready(Nil, process.new_selector()) },
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

// /// `eth_call` the `decimals` function of either an ERC20 contract.
// /// Panics if the provided contract does not have a function labelled "decimals"
// fn get_erc20_decimals(
//   rpc_url: Uri,
//   asset_contract: asset.AssetSmartContract(asset.ERC20),
// ) -> Result(eth.RpcResponse) {
//   // Grab contract and selector
//   let contract = asset.get_smart_contract(asset_contract)
//   let assert Ok(function_selector) = eth.get_function(contract, "decimals")

//   // call the RPC
//   eth.eth_call(contract, function_selector, <<>>, rpc_url)
// }

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
        |> result.replace_error(snag.new("result is not valid hexadecimal")),
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
        |> result.replace_error(snag.new("result is not valid hexadecimal")),
      )
      Ok(value)
    }
  }
}

fn handle_query_balance(
  builder: Builder,
  asset_id: String,
  account_id: String,
) -> Result(List(#(Int, prometheus.Labels, Dict(String, String)))) {
  use asset <- result.try(get_asset(builder, asset_id))
  use account <- result.try(asset.get_account(asset, account_id))
  let get_balance_result = case asset {
    asset.ERC20(_, _, _, asset_contract) ->
      query_erc20_balance(builder, account, asset_contract)
    asset.ERC721(_, _, _, asset_contract) ->
      query_erc721_balance(builder, account, asset_contract)
    asset.Native(_, _, _) -> query_native_balance(builder, account)
  }
  use #(balance_value, balance_decimals, asset_type, balance_extra_labels) <- result.try(
    get_balance_result,
  )
  let labels =
    prometheus.Labels(
      asset: asset_id,
      blockchain: builder.blockchain_id,
      rpc_url: builder.rpc_url |> uri.to_string,
      decimals: balance_decimals |> int.to_string,
      account: account_id,
      address: eth.address_to_string(account.address),
      blockchain_type: "evm",
      asset_type: asset_type,
    )
  Ok([#(balance_value, labels, balance_extra_labels)])
}

fn query_native_balance(
  builder: Builder,
  account: account.Account,
  // #(balance, decimals, asset_type, extra_labels)
) -> Result(#(Int, Int, String, Dict(String, String))) {
  use balance <- result.try(eth.eth_get_balance(
    builder.rpc_url,
    account.address,
  ))
  Ok(#(balance, default_native_decimals, "native", dict.new()))
}

fn query_erc20_balance(
  builder: Builder,
  account: account.Account,
  asset_contract: asset.AssetSmartContract(asset.ERC20),
  // #(balance, decimals, asset_type, extra_labels)
) -> Result(#(Int, Int, String, Dict(String, String))) {
  let contract_address =
    asset_contract
    |> asset.get_smart_contract
    |> eth.get_contract_address
    |> eth.address_to_string
  use rpc_response <- result.try(get_balance_from_contract_asset(
    builder.rpc_url,
    asset_contract,
    account.address,
  ))
  use balance <- result.try(parse_erc20_response(rpc_response))

  Ok(#(
    balance,
    default_native_decimals,
    "erc20",
    dict.from_list([#("contract_address", contract_address)]),
  ))
}

fn query_erc721_balance(
  builder: Builder,
  account: account.Account,
  asset_contract: asset.AssetSmartContract(asset.ERC721),
  // #(balance, decimals, asset_type, extra_labels)
) -> Result(#(Int, Int, String, Dict(String, String))) {
  let contract_address =
    asset_contract
    |> asset.get_smart_contract
    |> eth.get_contract_address
    |> eth.address_to_string
  use rpc_response <- result.try(get_balance_from_contract_asset(
    builder.rpc_url,
    asset_contract,
    account.address,
  ))
  use balance <- result.try(parse_erc721_response(rpc_response))

  Ok(#(
    balance,
    default_native_decimals,
    "erc721",
    dict.from_list([#("contract_address", contract_address)]),
  ))
}

fn handle_get_assets(builder: Builder) -> List(blockchain.Asset) {
  dict.fold(builder.assets, [], fn(assets, id, asset) {
    let #(kind, interval, timeout) = case asset {
      asset.ERC20(_, interval, timeout, _contract) -> #(
        "ERC20",
        interval,
        timeout,
      )
      asset.ERC721(_, interval, timeout, _contract) -> #(
        "ERC721",
        interval,
        timeout,
      )
      asset.Native(_, interval, timeout) -> #("Native", interval, timeout)
    }
    [blockchain.Asset(id, kind, interval, timeout), ..assets]
  })
}

fn handle_get_accounts(
  builder: Builder,
  asset_id: String,
) -> Result(List(blockchain.Account)) {
  use asset <- result.map(
    dict.get(builder.assets, asset_id)
    |> result.replace_error(snag.new("did not find asset id " <> asset_id)),
  )
  dict.fold(asset.accounts, [], fn(accounts, account_id, account) {
    [
      blockchain.Account(
        account_id,
        account.address |> eth.address_to_string,
        account.interval,
        account.timeout,
      ),
      ..accounts
    ]
  })
}
