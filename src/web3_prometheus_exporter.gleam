import chip
import exporter/blockchain
import exporter/http_server
import exporter/prometheus
import exporter/targets/evm
import exporter/targets/substrate
import exporter/util/glaml.{to_seq, to_string} as uglaml
import glaml
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/string
import snag.{type Result}

const default_restart_intensity = 1

const default_restart_period = 5

const default_port = 9855

const default_bind = "localhost"

pub fn main() {
  prometheus.init()
  let assert Ok([document]) = glaml.parse_file("config.yaml")
    as "expecting config.yaml file with exactly 1 yaml root"
  let assert Ok(registry) = chip.start(chip.Named("web3_prometheus_exporter"))
    as "failed to create chip registry"
  case supervisor_from_config(document, registry) {
    Error(e) -> panic as snag.pretty_print(e)
    Ok(_sup) -> io.println("successfully started supervisor")
  }
  let assert Ok(_) = http_server.start_server(default_port, default_bind)
  process.sleep_forever()
}

pub fn supervisor_from_config(
  config: glaml.Document,
  registry: chip.Registry(blockchain.Message, String),
) -> Result(erlsup.Supervisor(erlsup.Classic)) {
  let node = config.root
  use blockchain_nodes <- uglaml.try_parse(node, "blockchains", to_seq)

  let blockchain_results =
    list.index_map(blockchain_nodes, fn(blockchain_config, index) {
      parse_blockchain_config(blockchain_config, registry)
      |> snag.context("parsing blockchain #" <> int.to_string(index))
    })
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

fn parse_blockchain_config(
  blockchain_config: glaml.Node,
  registry: chip.Registry(blockchain.Message, String),
) -> Result(erlsup.ChildBuilder) {
  use kind <- uglaml.try_parse(blockchain_config, "type", to_string)
  case string.lowercase(kind) {
    "evm" ->
      evm.build_blockchain_child_process(blockchain_config, registry)
      |> snag.context("building EVM child supervisor from yaml config")
    "substrate" ->
      substrate.build_blockchain_child_process(blockchain_config, registry)
      |> snag.context("building Substrate child supervisor from yaml config")
    _ ->
      snag.error(
        "blockchain type \""
        <> kind
        <> "\" not found. Valid values (not case sensitive):\n\"EVM\"",
      )
  }
}
