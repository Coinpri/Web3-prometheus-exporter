import chip
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import snag.{type Result}

pub type Message {
  QueryBalance(
    asset_id: String,
    account_id: String,
    caller_subject: Subject(Result(Int)),
  )
  GetAssets(caller_subject: Subject(List(Asset)))
  GetAccounts(asset_id: String, caller_subject: Subject(Result(List(Account))))
}

pub type Asset {
  Asset(id: String, kind: String, details: Dict(String, String))
}

pub type Account {
  Account(id: String, address: String, details: Dict(String, String))
}

pub fn actor_to_child_builder(
  blockchain_actor: actor.Spec(Nil, Message),
  blockchain_id: String,
  registry: chip.Registry(Message, String),
) -> erlsup.ChildBuilder {
  let ethereum_on_started = fn(_) {
    let evm_process_result = actor.start_spec(blockchain_actor)
    let _ =
      result.map(evm_process_result, fn(evm_process_subject) {
        chip.register(registry, blockchain_id, evm_process_subject)
      })
    Nil
  }

  erlsup.new(erlsup.OneForOne)
  |> erlsup.supervisor_child(blockchain_id, ethereum_on_started)
}
