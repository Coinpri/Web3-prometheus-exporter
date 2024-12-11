import eth_crypto/eth.{type Address}

pub opaque type Account {
  Account(address: Address, request_timeout: Int, request_interval: Int)
}

const default_request_timeout = 10_000

const default_request_interval = 10_000

pub fn new(address address: Address) -> Account {
  Account(address, default_request_timeout, default_request_interval)
}

pub fn timeout(account account: Account, timeout_ms timeout_ms: Int) -> Account {
  case timeout_ms > 0 {
    False -> account
    True -> Account(..account, request_timeout: timeout_ms)
  }
}

pub fn interval(
  account account: Account,
  interval_ms interval_ms: Int,
) -> Account {
  case interval_ms > 0 {
    False -> account
    True -> Account(..account, request_interval: interval_ms)
  }
}

pub fn get_address(account account: Account) -> Address {
  account.address
}
