import exporter/util/result as uresult
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import snag.{type Result}
import themis
import themis/gauge
import themis/internal/metric
import themis/number

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

pub const mandatory_labels = [
  "asset", "blockchain", "rpc_url", "decimals", "account", "address",
  "blockchain_type", "asset_type",
]

const metrics_prefix = "web3_exporter"

const balance_metric_name = metrics_prefix <> "_balance"

pub fn init() -> Nil {
  themis.init()
  let assert Ok(_) = gauge.new(balance_metric_name, "Blockchain wallet balance")
    as "failed to create balance metric"
  Nil
}

pub fn set_balance(
  value: Int,
  labels: Labels,
  extra_labels: Dict(String, String),
) -> Result(Nil) {
  // gauge.set_gauge(
  //   registry,
  //   asset_id |> metric_name,
  //   labels |> extract_labels_values |> list.append(extra_labels),
  //   value,
  // )
  let all_labels =
    labels_to_dict(labels)
    |> dict.combine(extra_labels, fn(_base_label, extra_label) { extra_label })
  let observed_value = number.Int(value)
  gauge.observe(balance_metric_name, all_labels, observed_value)
  |> result.try_recover(fn(e) {
    case e {
      gauge.LabelError(_le) -> snag.error("invalid label name")
      gauge.MetricError(me) ->
        case me {
          metric.InvalidMetricName(e) ->
            snag.error("invalid metric name: " <> e)
          metric.InvalidWordInName(e) ->
            snag.error("invalid word in name: " <> e)
        }
      gauge.StoreError(_se) -> snag.error("unspecified store error")
    }
  })
}

pub fn labels_from_dict(
  dict: Dict(String, String),
) -> Result(#(Labels, Dict(String, String))) {
  use _, asset <- uresult.try_get(dict, "asset")
  use _, blockchain <- uresult.try_get(dict, "blockchain")
  use _, rpc_url <- uresult.try_get(dict, "rpc_url")
  use _, decimals <- uresult.try_get(dict, "decimals")
  use _, account <- uresult.try_get(dict, "account")
  use _, address <- uresult.try_get(dict, "address")
  use _, blockchain_type <- uresult.try_get(dict, "blockchain_type")
  use _, asset_type <- uresult.try_get(dict, "asset_type")
  Ok(#(
    Labels(
      asset: asset,
      blockchain: blockchain,
      rpc_url: rpc_url,
      decimals: decimals,
      account: account,
      address: address,
      blockchain_type: blockchain_type,
      asset_type: asset_type,
    ),
    dict.filter(dict, fn(key, _) { !list.contains(mandatory_labels, key) }),
  ))
}

pub fn export_metrics() -> String {
  let assert Ok(r) = themis.print()
  r
}

fn labels_to_dict(labels: Labels) -> Dict(String, String) {
  dict.from_list([
    #("asset", labels.asset),
    #("blockchain", labels.blockchain),
    #("rpc_url", labels.rpc_url),
    #("decimals", labels.decimals),
    #("account", labels.account),
    #("address", labels.address),
    #("blockchain_type", labels.blockchain_type),
    #("asset_type", labels.asset_type),
  ])
}
