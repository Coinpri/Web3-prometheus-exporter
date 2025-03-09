import chip
import exporter/blockchain
import exporter/util/glaml.{to_seq, to_string} as uglaml
import glaml
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/uri
import snag.{type Result}

/// Returns an entire otp `erlang_supervisor.ChildBuilder` from the blockchain yaml
/// node (and prometheus subject, and chip registry). The `ChildBuilder` can then
/// be added to a `Builder` with `erlang_supervisor.add`, or started on a running
/// supervisor with `erlang_supervisor.start_child`.
/// If using a `otp/supervisor` instead, a different function will be needed.
/// See `example.config.yaml` for config example.
pub fn build_blockchain_child_process(
  config config: glaml.Node,
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

    // Starting here, we have blockchain_id, rpc_url, assets, optional_blockchain_interval, optional_blockchain_timeout
    todo as "make a substrate library with substrate accounts and basic RPC/WS calls"
  }
}
