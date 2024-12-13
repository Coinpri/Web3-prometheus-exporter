import eth_crypto/eth
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import snag
import web3_prometheus_exporter/blockchain
import web3_prometheus_exporter/prometheus
import web3_prometheus_exporter/targets/evm/account
import web3_prometheus_exporter/targets/evm/asset
import web3_prometheus_exporter/targets/evm/blockchain as evm_blockchain

import chip
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/uri

import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn evm_test() {
  let blockchain_name = "Ethereum Mainnet"
  let assert Ok(rpc_url) = uri.parse("https://rpc.ankr.com/eth")
  let assert Ok(registry) = chip.start(chip.Unnamed)
  // Creating 3 accounts for address 0:
  // native eth account
  // 0x0 account
  // some random NFT account (used as burn only wallet, seems good)
  let assert Ok(address) =
    eth.address_from_string("0x0000000000000000000000000000000000000000")
  let assert Ok(address_non_0) =
    eth.address_from_string("0x0000000000000000000000000000000000000001")
  let account = account.new(address)
  let account_non_0 = account.new(address_non_0)
  let native =
    asset.new_native()
    |> asset.add_account(account, "address 0")
    |> asset.add_account(account_non_0, "address 1")

  let erc20 =
    asset.new_erc20("0xB8fda5AEe55120247F16225feFf266dfdB381D4C")
    |> should.be_ok
    |> asset.add_account(account, "address 0")
  let erc721 =
    asset.new_erc721("0x48c11b86807627af70a34662d4865cf854251663")
    |> should.be_ok
    |> asset.add_account(account, "address 0")
    |> asset.add_account(account_non_0, "address 1")

  let blockchain_builder =
    evm_blockchain.new(rpc_url)
    |> evm_blockchain.add_asset(native, "Ether")
    |> evm_blockchain.add_asset(erc20, "0x0")
    |> evm_blockchain.add_asset(erc721, "swEXIT")
  let blockchain_actor = evm_blockchain.to_actor(blockchain_builder)

  let assert Ok(_sup) =
    erlsup.new(erlsup.OneForOne)
    |> erlsup.add({
      erlsup.worker_child(blockchain_name, fn() {
        blockchain_actor
        |> actor.start_spec
        |> result.map(fn(subject) {
          chip.register(registry, blockchain_name, subject)
          process.subject_owner(subject)
        })
      })
      |> erlsup.significant(True)
      |> erlsup.restart(erlsup.Transient)
    })
    |> erlsup.auto_shutdown(erlsup.AllSignificant)
    |> erlsup.start_link

  let assert [blockchain_subject] =
    chip.members(registry, "Ethereum Mainnet", 50)

  let addr_0_balance =
    process.try_call(
      blockchain_subject,
      blockchain.QueryBalance("Ether", "address 0", _),
      1000,
    )
    |> should.be_ok
    |> should.be_ok

  should.be_true(addr_0_balance > { 13_433_191_104_394_091_468_880 })

  let addr_0_balance =
    process.try_call(
      blockchain_subject,
      blockchain.QueryBalance("0x0", "address 0", _),
      1000,
    )
    |> should.be_ok
    |> should.be_ok

  should.be_true(
    addr_0_balance > { 100_000_000_000_000_000_000_000_000_000_000_000_000 },
  )

  process.try_call(
    blockchain_subject,
    blockchain.QueryBalance("swEXIT", "address 0", _),
    1000,
  )
  |> should.be_ok
  |> should.be_error
  |> should.equal(
    snag.Snag(
      "rpc error: code: 3 | message: \"execution reverted: ERC721: address zero is not a valid owner\"",
      [],
    ),
  )

  let addr_1_balance =
    process.try_call(
      blockchain_subject,
      blockchain.QueryBalance("swEXIT", "address 1", _),
      1000,
    )
    |> should.be_ok
    |> should.be_ok

  should.be_true(addr_1_balance == 0)
}

pub fn evm_otp_test() {
  let registry = chip.start(chip.Unnamed) |> should.be_ok
  let prometheus_subject = process.new_subject()

  let account =
    account.new(
      eth.address_from_string("0x0000000000000000000000000000000000000000")
      |> should.be_ok,
    )
  let native = asset.new_native() |> asset.add_account(account, "address 0")

  let ethereum_actor =
    evm_blockchain.new("https://rpc.ankr.com/eth" |> uri.parse |> should.be_ok)
    |> evm_blockchain.add_asset(native, "Ether")
    |> evm_blockchain.to_actor

  let arbitrum_actor =
    evm_blockchain.new(
      "https://arb1.arbitrum.io/rpc" |> uri.parse |> should.be_ok,
    )
    |> evm_blockchain.add_asset(native, "Ether")
    |> evm_blockchain.to_actor

  let ethereum_supervisor =
    blockchain.actor_to_child_builder(
      ethereum_actor,
      "Ethereum Mainnet",
      prometheus_subject,
      registry,
      Some(1000),
      Some(500),
    )

  let arbitrum_supervisor =
    blockchain.actor_to_child_builder(
      arbitrum_actor,
      "Arbitrum One",
      prometheus_subject,
      registry,
      Some(1000),
      Some(500),
    )

  let _top_supervisor =
    erlsup.new(erlsup.OneForOne)
    |> erlsup.add(ethereum_supervisor)
    |> erlsup.add(arbitrum_supervisor)
    |> erlsup.start_link
    |> should.be_ok

  let assert [ethereum_supervisor_subject] =
    chip.members(registry, "Ethereum Mainnet", 10)
  let assert [arbitrum_supervisor_subject] =
    chip.members(registry, "Arbitrum One", 10)

  process.try_call(
    ethereum_supervisor_subject,
    blockchain.QueryBalance("Ether", "address 0", _),
    1000,
  )
  |> should.be_ok
  |> should.be_ok
  |> fn(compare_with) { compare_with >= 13_433_191_104_394_091_468_880 }
  |> should.be_true

  process.try_call(
    arbitrum_supervisor_subject,
    blockchain.QueryBalance("Ether", "address 0", _),
    1000,
  )
  |> should.be_ok
  |> should.be_ok
  |> fn(compare_with) { compare_with >= 21_007_073_506_420_136_152 }
  |> should.be_true

  process.try_call(ethereum_supervisor_subject, blockchain.GetAssets(_), 10)
  |> should.be_ok
  |> should.equal([blockchain.Asset("Ether", "Native", dict.new(), None, None)])
  process.try_call(arbitrum_supervisor_subject, blockchain.GetAssets(_), 10)
  |> should.be_ok
  |> should.equal([blockchain.Asset("Ether", "Native", dict.new(), None, None)])

  process.try_call(
    ethereum_supervisor_subject,
    blockchain.GetAccounts("Ether", _),
    10,
  )
  |> should.be_ok
  |> should.be_ok
  |> should.equal([
    blockchain.Account(
      "address 0",
      "0x0000000000000000000000000000000000000000",
      dict.new(),
      None,
      None,
    ),
  ])
  process.try_call(
    arbitrum_supervisor_subject,
    blockchain.GetAccounts("Ether", _),
    10,
  )
  |> should.be_ok
  |> should.be_ok
  |> should.equal([
    blockchain.Account(
      "address 0",
      "0x0000000000000000000000000000000000000000",
      dict.new(),
      None,
      None,
    ),
  ])
  let prometheus.UpdateBalance(new_balance_ether, labels_ether) =
    process.receive(prometheus_subject, 1500) |> should.be_ok
  let prometheus.UpdateBalance(new_balance_arbitrum, labels_arbitrum) =
    process.receive(prometheus_subject, 1500) |> should.be_ok

  should.be_true(new_balance_ether >= 13_434_239_746_187_261_108_342)
  should.equal(
    labels_ether,
    dict.from_list([
      #("account", "address 0"),
      #("address", "0x0000000000000000000000000000000000000000"),
      #("asset", "Ether"),
    ]),
  )

  should.be_true(new_balance_arbitrum >= 21_007_078_971_312_777_512)
  should.equal(
    labels_arbitrum,
    dict.from_list([
      #("account", "address 0"),
      #("address", "0x0000000000000000000000000000000000000000"),
      #("asset", "Ether"),
    ]),
  )
  let assert Error(_) =
    process.receive(prometheus_subject, 1500)
    |> result.map(fn(_) {
      snag.error(
        "if this fails (unexpectedly returns an Ok value), try the test again. It's possible the ethereum or arbitrum balance for address 0 was changed in between the two runs (1 second window)",
      )
    })
}
