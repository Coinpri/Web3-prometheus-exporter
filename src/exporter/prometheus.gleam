import gleam/dict.{type Dict}
import gleam/result
import promgleam/metrics/gauge
import promgleam/registry
import snag.{type Result}

//TODO: replace any usage of this Message with `set_balance`
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
  )
}

const mandatory_labels = [
  "asset", "blockchain", "rpc_url", "decimals", "account", "address",
  "blockchain_type", "asset_type",
]

const registry = "default"

const metrics_prefix = "web3_exporter"

pub fn init_balance(asset_id: String) -> Result(Nil) {
  gauge.create_gauge(
    registry,
    metric_name(asset_id),
    "Balance for asset " <> asset_id,
    mandatory_labels,
  )
  |> result.try_recover(fn(msg) { snag.error(msg) })
}

pub fn set_balance(asset_id: String, value: Int, labels: Labels) -> Result(Nil) {
  gauge.set_gauge(
    registry,
    asset_id |> metric_name,
    labels |> extract_labels_values,
    value,
  )
  |> result.try_recover(fn(msg) { snag.error(msg) })
}

pub fn export_metrics() -> String {
  registry.print_as_text(registry)
}

fn extract_labels_values(labels: Labels) -> List(String) {
  [
    labels.account,
    labels.address,
    labels.asset,
    labels.blockchain,
    labels.asset_type,
    labels.blockchain_type,
    labels.rpc_url,
    labels.decimals,
  ]
}

fn metric_name(asset_id: String) -> String {
  metrics_prefix <> "_balance_" <> asset_id
}
