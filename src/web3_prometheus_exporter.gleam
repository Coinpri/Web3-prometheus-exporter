import chip
import eth_crypto/eth
import gleam/erlang/process
import gleam/io
import gleam/option.{None}

// import web3_prometheus_exporter/blockchain/evm
import web3_prometheus_exporter/supervisor

pub fn main() {
  todo
  // let #(sup, reg) = supervisor.start()
  // let subject = process.new_subject()
  // let subject2 = process.new_subject()
  // let assert [blockchain_subject] =
  //   chip.members(reg, supervisor.Group("Ethereum Mainnet", None), 50)
  // let assert Ok(address) =
  //   eth.address_from_string("0xD3a22590f8243f8E83Ac230D1842C9Af0404C4A1")

  // process.send(blockchain_subject, evm.QueryNativeBalance(address, subject))
  // let assert Ok(value) = process.receive(subject, 10)
  // io.debug(value)
  // process.send(
  //   blockchain_subject,
  //   evm.ViewCallContract(
  //     "doesnt matter",
  //     "doesnt matter",
  //     "doesnt matter",
  //     subject2,
  //   ),
  // )
  // let assert Ok(value) = process.receive(subject2, 10)
  // io.println(value)
}
