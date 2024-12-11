import chip
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/uri

// import web3_prometheus_exporter/blockchain/evm.{type Asset}

pub type Group {
  Group(blockchain_name: String, asset_name: Option(String))
}
// pub fn start() -> #(
//   erlsup.Supervisor,
//   Subject(chip.Message(evm.Message, Group)),
// ) {
//   let blockchain_name = "Ethereum Mainnet"
//   let assert Ok(rpc_url) = uri.parse("https://rpc.ankr.com/eth")
//   let assert Ok(registry) = chip.start(chip.Unnamed)

//   let assert Ok(sup) =
//     erlsup.new(erlsup.OneForOne)
//     |> erlsup.add({
//       erlsup.worker_child(blockchain_name, fn() {
//         evm.new(blockchain_name, rpc_url)
//         |> evm.to_actor
//         |> actor.start_spec
//         |> result.map(fn(subject) {
//           chip.register(registry, Group(blockchain_name, None), subject)
//           process.subject_owner(subject)
//         })
//       })
//       |> erlsup.significant(True)
//       |> erlsup.restart(erlsup.Transient)
//     })
//     |> erlsup.auto_shutdown(erlsup.AllSignificant)
//     |> erlsup.start_link
//   #(sup, registry)
// }
