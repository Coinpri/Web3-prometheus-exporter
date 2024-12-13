import chip
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/string
import gleam/yielder
import snag
import web3_prometheus_exporter/prometheus

pub type Message {
  QueryBalance(
    asset_id: String,
    account_id: String,
    caller_subject: Subject(snag.Result(Int)),
  )
  GetAssets(caller_subject: Subject(List(Asset)))
  GetAccounts(
    asset_id: String,
    caller_subject: Subject(snag.Result(List(Account))),
  )
}

pub type Asset {
  Asset(
    id: String,
    kind: String,
    details: Dict(String, String),
    timeout: Option(Int),
    interval: Option(Int),
  )
}

pub type Account {
  Account(
    id: String,
    address: String,
    details: Dict(String, String),
    timeout: Option(Int),
    interval: Option(Int),
  )
}

const default_timeout = 10_000

const default_interval = 15_000

pub fn actor_to_child_builder(
  blockchain_actor blockchain_actor: actor.Spec(Nil, Message),
  blockchain_id blockchain_id: String,
  prometheus_subject prometheus_subject: Subject(prometheus.Message),
  registry registry: chip.Registry(Message, String),
  blockchain_interval blockchain_interval: Option(Int),
  blockchain_timeout blockchain_timeout: Option(Int),
) -> erlsup.ChildBuilder {
  let start_supervisor_child = fn(blockchain_supervisor) {
    let evm_process_result = actor.start_spec(blockchain_actor)
    let assert Ok(_) =
      result.map(evm_process_result, fn(evm_process_subject) {
        chip.register(registry, blockchain_id, evm_process_subject)
        let assets = process.call(evm_process_subject, GetAssets, 100)
        use asset <- list.each(assets)
        let assert Ok(accounts) =
          process.call(evm_process_subject, GetAccounts(asset.id, _), 100)
        use account <- list.each(accounts)

        let timeout =
          option.unwrap(
            account.timeout,
            option.unwrap(
              asset.timeout,
              option.unwrap(blockchain_timeout, default_timeout),
            ),
          )
        let interval =
          option.unwrap(
            account.interval,
            option.unwrap(
              asset.interval,
              option.unwrap(blockchain_interval, default_interval),
            ),
          )

        let timer_child =
          erlsup.worker_child(
            asset.id <> "-" <> account.id,
            make_timer_loop(
              evm_process_subject,
              prometheus_subject,
              asset.id,
              asset.details,
              account.id,
              account.address,
              account.details,
              timeout,
              interval,
            ),
          )
          |> erlsup.timeout(timeout + interval + 10_000)
        blockchain_supervisor
        |> erlsup.start_child(timer_child)
        blockchain_supervisor
        |> erlsup.get_pid
        |> erlsup.erlang_get_childspec(
          { asset.id <> "-" <> account.id } |> dynamic.from,
        )
      })

    Nil
  }

  erlsup.new(erlsup.OneForOne)
  |> erlsup.supervisor_child(blockchain_id, start_supervisor_child)
}

fn make_timer_loop(
  blockchain_subject: Subject(Message),
  prometheus_subject: Subject(prometheus.Message),
  asset_id: String,
  asset_details: Dict(String, String),
  account_id: String,
  account_address: String,
  account_details: Dict(String, String),
  timeout_ms: Int,
  interval_ms: Int,
) -> fn() -> Result(Pid, Nil) {
  fn() {
    Ok(process.start(
      fn() {
        let subject = process.new_subject()
        use last_balance, _ <- yielder.fold(yielder.repeat(Nil), 0)

        let _timer =
          process.send_after(
            blockchain_subject,
            interval_ms,
            QueryBalance(asset_id, account_id, subject),
          )

        // let iters = { interval_ms / 4000 } + 1
        // let sleep_for = interval_ms / iters
        // yielder.each(yielder.range(1, iters), fn(_) {
        //   process.sleep(sleep_for |> io.debug)
        // })

        let assert Ok(balance_result) =
          process.receive(subject, interval_ms + timeout_ms + 10_000)
        case balance_result {
          Error(_) -> last_balance
          Ok(new_balance) if new_balance == last_balance -> last_balance
          Ok(new_balance) -> {
            let labels =
              dict.from_list([
                #("asset", asset_id),
                #("account", account_id),
                #("address", account_address),
              ])
              |> dict.combine(asset_details, fn(_, _) {
                panic as "found same label keys in asset details"
              })
              |> dict.combine(account_details, fn(_, _) {
                panic as "found same label keys in account details"
              })
            process.send(
              prometheus_subject,
              prometheus.UpdateBalance(new_balance, labels),
            )
            new_balance
          }
        }
      },
      False,
    ))
  }
}
