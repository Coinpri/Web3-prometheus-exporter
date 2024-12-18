import chip
import eth_crypto/eth
import exporter/blockchain
import exporter/targets/evm/account
import exporter/targets/evm/asset
import exporter/targets/evm/blockchain as evm_blockchain
import exporter/util/glaml.{to_seq, to_string} as uglaml
import glaml
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/string
import gleam/uri
import snag.{type Result}

/// Returns an entire otp `erlang_supervisor.ChildBuilder` from the blockchain yaml
/// node (and prometheus subject, and chip registry). The `ChildBuilder` can then
/// be added to a `Builder` with `erlang_supervisor.add`, or started on a running
/// supervisor with `erlang_supervisor.start_child`.
/// If using a `otp/supervisor` instead, a different function will be needed.
/// See `example.config.yaml` for config example.
pub fn build_blockchain_child_process(
  config config: glaml.DocNode,
  blockchain_process_registry registry: chip.Registry(
    blockchain.Message,
    String,
  ),
) -> Result(erlsup.ChildBuilder) {
  {
    // extracting and parsing glaml nodes
    use blockchain_id <- uglaml.try_parse(config, "id", to_string)
    use rpc_url_string <- uglaml.try_parse(config, "rpc_url", to_string)
    use rpc_url <- result.try(
      uri.parse(rpc_url_string)
      |> result.replace_error(snag.new(
        "failed to parse rpc url \"" <> rpc_url_string <> "\"",
      )),
    )
    use assets <- uglaml.try_parse(config, "assets", to_seq)

    // extracting and parsing optional `interval` and `timeout` values
    let #(optional_blockchain_interval, optional_blockchain_timeout) =
      uglaml.extract_optional_times(config)

    // extracting and parsing `assets`
    use assets <- result.map(
      parse_assets(assets) |> snag.context("parsing assets"),
    )

    // creating new `evm_blockchain` builder, adding assets to it,
    // building an `otp/actor` from it,
    // and converting that actor to a `erlang_supervisor.ChildBuilder`
    evm_blockchain.new(blockchain_id, rpc_url)
    |> evm_blockchain.add_assets(assets)
    |> evm_blockchain.to_actor
    |> blockchain.actor_to_child_builder(
      blockchain_id,
      registry,
      optional_blockchain_interval,
      optional_blockchain_timeout,
    )
  }
}

/// Extract a dict of assets from a list of `glaml.DocNode`
/// Example:
/// ```
/// ...
///   - id: "my asset"
///     type: "erc20"
///     contract_address: "0xFEDC...21"
///     accounts:
///       ...
/// -> #("my asset", "0x123...EF" |> to_address |> to_erc20_contract |> to_asset)
/// |> dict.from_list
/// ```
/// Returns an `Error` if any of the assets cannot be parsed.
fn parse_assets(
  assets: List(glaml.DocNode),
) -> Result(Dict(String, asset.Asset)) {
  let assets_result =
    {
      use asset_node, index <- list.index_map(assets)

      {
        // extract asset fields
        use asset_id <- uglaml.try_parse(asset_node, "id", to_string)
        use asset_type_string <- uglaml.try_parse(asset_node, "type", to_string)
        use asset_accounts <- uglaml.try_parse(asset_node, "accounts", to_seq)

        // extracting and parsing optional `interval` and `timeout` values
        let #(optional_asset_interval, optional_asset_timeout) =
          uglaml.extract_optional_times(asset_node)

        // parsing accounts
        use accounts <- result.try(
          parse_accounts(asset_accounts) |> snag.context("parsing accounts"),
        )

        // parsing the asset's `type` field.
        // correct values (case-insensitive):
        // - "native"
        // - "erc20" with `contract_address` field
        // - "erc721" with `contract_address` field
        use asset <- result.try(case string.lowercase(asset_type_string) {
          "native" -> Ok(asset.new_native())
          "erc20" ->
            parse_erc20_asset(asset_node)
            |> snag.context("attempting to parse erc20 asset")
          "erc721" ->
            parse_erc721_asset(asset_node)
            |> snag.context("attempting to parse erc721 asset")
          other -> snag.error("unrecognized evm asset type \"" <> other <> "\"")
        })

        // Returning 2-tuple to build the final Dict from
        // #("asset id", newly_built_asset)
        Ok(#(
          asset_id,
          asset.add_accounts(
            asset
              |> asset.set_interval(optional_asset_interval)
              |> asset.set_timeout(optional_asset_timeout),
            accounts,
          ),
        ))
      }
      |> snag.context("parsing asset #" <> int.to_string(index))
    }
    // The previous block returns a `List(Result(#(String, asset.Asset)))`
    // Ensure all items in the list are Ok
    |> result.all
  result.map(assets_result, fn(assets) { dict.from_list(assets) })
}

/// Extract a dict of accounts from a list `glaml.DocNode`
/// Example:
/// ```
/// ...
///     - id: "my account"
///       address: "0x123456789...EF"
/// -> #("my account", "0x123...EF" |> to_address |> to_account)
/// |> dict.from_list
/// ```
/// Returns an `Error` if any of the accounts cannot be parsed.
fn parse_accounts(
  accounts: List(glaml.DocNode),
) -> Result(Dict(String, account.Account)) {
  let account_results =
    {
      use account_node, index <- list.index_map(accounts)

      {
        // extract account fields
        use account_id <- uglaml.try_parse(account_node, "id", to_string)
        use addr_string <- uglaml.try_parse(account_node, "address", to_string)

        // extract and parse optional `interval` and `timeout` values
        let #(optional_account_interval, optional_account_timeout) =
          uglaml.extract_optional_times(account_node)

        // parse the given `address` into an EVM address object
        use account_address <- result.try(eth.address_from_string(addr_string))

        // Returning 2-tuple to build the final Dict from
        // #("account id", newly_built_account)
        Ok(#(
          account_id,
          account.new(account_address)
            |> account.timeout(optional_account_timeout)
            |> account.interval(optional_account_interval),
        ))
      }
      |> snag.context("parsing account #" <> int.to_string(index))
    }
    // The previous block returns a `List(Result(#(String, account.Account)))`
    // Ensure all items in the list are Ok
    |> result.all
  result.map(account_results, fn(accounts) { dict.from_list(accounts) })
}

/// Basically just extracts the non-standard `contract_address` field
/// from an asset glaml node. Returns an `Error` if not found.
/// Builds a new `asset.ERC20` from the found smart contract address
fn parse_erc20_asset(asset_node: glaml.DocNode) -> Result(asset.Asset) {
  use contract_address <- result.try(case
    glaml.sugar(asset_node, "contract_address")
  {
    Ok(glaml.DocNodeStr(address)) -> Ok(address)
    _ -> snag.error("could not parse field \"contract_address\"")
  })
  asset.new_erc20(contract_address)
}

/// Basically just extracts the non-standard `contract_address` field
/// from an asset glaml node. Returns an `Error` if not found.
/// Builds a new `asset.ERC721` from the found smart contract address
fn parse_erc721_asset(asset_node: glaml.DocNode) -> Result(asset.Asset) {
  use contract_address <- result.try(case
    glaml.sugar(asset_node, "contract_address")
  {
    Ok(glaml.DocNodeStr(address)) -> Ok(address)
    _ -> snag.error("could not parse field \"contract_address\"")
  })
  asset.new_erc721(contract_address)
}
