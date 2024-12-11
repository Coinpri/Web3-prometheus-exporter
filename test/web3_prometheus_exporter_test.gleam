import eth_crypto/eth
import gleam/io
import snag
import web3_prometheus_exporter/targets/evm/account
import web3_prometheus_exporter/targets/evm/asset
import web3_prometheus_exporter/targets/evm/blockchain

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
    blockchain.new(blockchain_name, rpc_url)
    |> blockchain.add_asset(native, "Ether")
    |> blockchain.add_asset(erc20, "0x0")
    |> blockchain.add_asset(erc721, "swEXIT")
  let blockchain_actor = blockchain.to_actor(blockchain_builder)

  let assert Ok(sup) =
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

  should.be_true(addr_0_balance > { 13_431_000_000_000_000_000_000 })

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
