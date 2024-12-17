import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set
import promgleam/metrics/gauge
import promgleam/registry
import snag.{type Result}

pub type Message {
  UpdateBalance(new_balance: Int, labels: Dict(String, String))
}

pub type Labels {
  Labels(
    asset: String,
    blockchain: String,
    rpc_url: String,
    decimals: String,
    account: String,
    address: String,
    blockchain_type: String,
    asset_type: String,
    contract_address: Option(String),
    balance_type: Option(String),
  )
}

const mandatory_labels = [
  "asset", "blockchain", "rpc_url", "decimals", "account", "address",
  "blockchain_type", "asset_type",
]

const optional_labels = ["contract_address", "balance_type"]

const registry = "default"

const metrics_prefix = "web3_exporter"

pub fn init_balance(asset_id: String, extra_labels: List(String)) -> Result(Nil) {
  let extra_labels =
    list.filter(extra_labels, fn(label) {
      list.contains(optional_labels, label)
    })
  gauge.create_gauge(
    registry,
    metric_name(asset_id),
    "Balance for the " <> asset_id <> " asset",
    list.append(mandatory_labels, extra_labels),
  )
  |> result.try_recover(fn(msg) { snag.error(msg) })
}

pub fn set_balance(
  asset_id: String,
  value: Int,
  labels: Dict(String, String),
) -> Result(Nil) {
  use labels <- result.try(
    label_dict_to_list(labels)
    |> snag.context("extracting labels for asset " <> asset_id),
  )
  gauge.set_gauge(registry, asset_id |> metric_name, labels, value)
  |> result.try_recover(fn(msg) { snag.error(msg) })
}

pub fn export_metrics() -> String {
  registry.print_as_text(registry)
}

fn label_dict_to_list(labels: Dict(String, String)) -> Result(List(String)) {
  use <- bool.guard(
    !set.is_subset(
      set.from_list(mandatory_labels),
      set.from_list(dict.keys(labels)),
    ),
    snag.error("given labels are missing mandatory labels"),
  )
  Ok(
    dict.filter(labels, fn(label_name, _label_value) {
      list.contains(list.append(mandatory_labels, optional_labels), label_name)
    })
    |> dict.values,
  )
}

fn metric_name(asset_id: String) -> String {
  metrics_prefix <> "_balance_" <> asset_id
}
