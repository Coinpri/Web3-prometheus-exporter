import chip
import eth_crypto/eth
import glaml
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/string
import gleam/uri
import snag.{type Result}
import web3_prometheus_exporter/blockchain
import web3_prometheus_exporter/prometheus
import web3_prometheus_exporter/targets/evm/account
import web3_prometheus_exporter/targets/evm/asset
import web3_prometheus_exporter/targets/evm/blockchain as evm_blockchain

// TODO:
// write comments for this code
// write some tests for it
// go through the rest of the code and comment it as well
// consider writing some documentation even (although might be a bit early for that)

pub fn build_blockchain_child_process(
  config config: glaml.DocNode,
  prometheus_subject subject: Subject(prometheus.Message),
  blockchain_process_registry registry: chip.Registry(
    blockchain.Message,
    String,
  ),
) -> Result(erlsup.ChildBuilder) {
  use blockchain_id_node <- try_parse(config, "id")
  use rpc_url_node <- try_parse(config, "rpc_url")
  use assets_node <- try_parse(config, "assets")

  // Checking types for all the fields
  use blockchain_id <- result.try(case blockchain_id_node {
    glaml.DocNodeStr(blockchain_id) -> Ok(blockchain_id)
    _ -> snag.error("blockchain id field should be a string")
  })
  use rpc_url <- result.try(case rpc_url_node {
    glaml.DocNodeStr(rpc_url) ->
      uri.parse(rpc_url)
      |> result.try_recover(fn(_) {
        snag.error(
          "blockchain rpc url field is not a valid url: \"" <> rpc_url <> "\"",
        )
      })
    _ -> snag.error("blockchain rpc url field should be a string")
  })
  use assets <- result.try(case assets_node {
    glaml.DocNodeSeq(asset_nodes) -> Ok(asset_nodes)
    _ -> snag.error("blockchain field \"assets\" should be a list")
  })

  let #(optional_blockchain_interval, optional_blockchain_timeout) =
    extract_optional_times(config)

  use assets <- result.map(
    parse_assets(assets) |> snag.context("parsing assets"),
  )

  evm_blockchain.new(rpc_url)
  |> evm_blockchain.add_assets(assets)
  |> evm_blockchain.to_actor
  |> blockchain.actor_to_child_builder(
    blockchain_id,
    subject,
    registry,
    optional_blockchain_interval,
    optional_blockchain_timeout,
  )
}

fn parse_assets(
  assets: List(glaml.DocNode),
) -> Result(Dict(String, asset.Asset)) {
  let assets_result =
    {
      use asset_node, index <- list.index_map(assets)

      {
        use asset_id_node <- try_parse(asset_node, "id")
        use asset_type_node <- try_parse(asset_node, "type")
        use asset_accounts_node <- try_parse(asset_node, "accounts")

        use asset_id <- result.try(case asset_id_node {
          glaml.DocNodeStr(asset_id) -> Ok(asset_id)
          _ -> snag.error("blockchain field \"id\" should be a string")
        })
        use asset_type_string <- result.try(case asset_type_node {
          glaml.DocNodeStr(asset_type) -> Ok(asset_type)
          _ -> snag.error("blockchain field \"type\" should be a string")
        })
        use asset_accounts <- result.try(case asset_accounts_node {
          glaml.DocNodeSeq(asset_accounts) -> Ok(asset_accounts)
          _ -> snag.error("blockchain field \"id\" should be a list")
        })

        let #(optional_asset_interval, optional_asset_timeout) =
          extract_optional_times(asset_node)

        use accounts <- result.try(
          parse_accounts(asset_accounts) |> snag.context("parsing accounts"),
        )
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
    |> result.all
  use assets <- result.map(assets_result)
  dict.from_list(assets)
}

fn parse_accounts(
  accounts: List(glaml.DocNode),
) -> Result(Dict(String, account.Account)) {
  let account_results =
    {
      use account_node, index <- list.index_map(accounts)

      {
        use account_id_node <- try_parse(account_node, "id")
        use account_address_node <- try_parse(account_node, "address")

        use account_id <- result.try(case account_id_node {
          glaml.DocNodeStr(account_id) -> Ok(account_id)
          _ -> snag.error("blockchain field \"id\" should be a string")
        })
        use account_address_string <- result.try(case account_address_node {
          glaml.DocNodeStr(account_address) -> Ok(account_address)
          _ -> snag.error("blockchain field \"address\" should be a string")
        })

        let #(optional_account_interval, optional_account_timeout) =
          extract_optional_times(account_node)

        use account_address <- result.try(eth.address_from_string(
          account_address_string,
        ))
        Ok(#(
          account_id,
          account.new(account_address)
            |> account.timeout(optional_account_timeout)
            |> account.interval(optional_account_interval),
        ))
      }
      |> snag.context("parsing account #" <> int.to_string(index))
    }
    |> result.all
  use accounts <- result.map(account_results)
  dict.from_list(accounts)
}

fn extract_optional_times(node: glaml.DocNode) -> #(Option(Int), Option(Int)) {
  let interval = case glaml.sugar(node, "interval") {
    Ok(glaml.DocNodeInt(interval)) -> Some(interval)
    _ -> None
  }
  let timeout = case glaml.sugar(node, "timeout") {
    Ok(glaml.DocNodeInt(timeout)) -> Some(timeout)
    _ -> None
  }
  #(interval, timeout)
}

fn try_parse(
  node: glaml.DocNode,
  field: String,
  apply: fn(glaml.DocNode) -> Result(b),
) -> Result(b) {
  let r =
    glaml.sugar(node, field)
    |> result.try_recover(fn(_) {
      snag.error("could not parse field \"" <> field <> "\"")
    })
  result.try(r, apply)
}

fn parse_erc20_asset(asset_node: glaml.DocNode) -> Result(asset.Asset) {
  use contract_address <- result.try(case
    glaml.sugar(asset_node, "contract_address")
  {
    Ok(glaml.DocNodeStr(address)) -> Ok(address)
    _ -> snag.error("could not parse field \"contract_address\"")
  })
  asset.new_erc20(contract_address)
}

fn parse_erc721_asset(asset_node: glaml.DocNode) -> Result(asset.Asset) {
  use contract_address <- result.try(case
    glaml.sugar(asset_node, "contract_address")
  {
    Ok(glaml.DocNodeStr(address)) -> Ok(address)
    _ -> snag.error("could not parse field \"contract_address\"")
  })
  asset.new_erc721(contract_address)
}
