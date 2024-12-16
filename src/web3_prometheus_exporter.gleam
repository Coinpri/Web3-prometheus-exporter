import chip
import exporter/blockchain
import exporter/prometheus
import exporter/targets/evm
import exporter/util/glaml.{to_seq, to_string} as uglaml
import glaml
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/string
import snag.{type Result}

const default_restart_intensity = 1

const default_restart_period = 5

pub fn supervisor_from_config(
  config: glaml.Document,
  prometheus_subject: Subject(prometheus.Message),
  registry: chip.Registry(blockchain.Message, String),
) -> Result(erlsup.Supervisor(erlsup.Classic)) {
  let node = glaml.doc_node(config)
  use blockchain_nodes <- uglaml.try_parse(node, "blockchains", to_seq)

  let blockchain_results =
    list.map(blockchain_nodes, parse_blockchain(_, prometheus_subject, registry))
    |> result.all
  use blockchains <- result.try(blockchain_results)

  let builder =
    erlsup.new(erlsup.OneForOne)
    |> erlsup.restart_tolerance(
      default_restart_intensity,
      default_restart_period,
    )

  list.fold(blockchains, builder, erlsup.add)
  |> erlsup.start_link
  |> result.replace_error(snag.new("failed to start top-level supervisor"))
}

fn parse_blockchain(
  blockchain_config: glaml.DocNode,
  prometheus_subject: Subject(prometheus.Message),
  registry: chip.Registry(blockchain.Message, String),
) -> Result(erlsup.ChildBuilder) {
  use kind <- uglaml.try_parse(blockchain_config, "type", to_string)
  case string.lowercase(kind) {
    "evm" ->
      evm.build_blockchain_child_process(
        blockchain_config,
        prometheus_subject,
        registry,
      )
    _ -> snag.error("")
  }
}
