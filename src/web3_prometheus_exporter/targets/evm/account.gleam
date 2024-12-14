import eth_crypto/eth.{type Address}
import gleam/option.{type Option, None, Some}

/// An account is simply an EVM address with optional timers
/// which determine the frequency and tolerance of querying
/// blockchain data for that account.
pub opaque type Account {
  Account(address: Address, timeout: Option(Int), interval: Option(Int))
}

/// Return a new EVM account from an EVM address.
pub fn new(address address: Address) -> Account {
  Account(address, None, None)
}

/// Set an account's optional timeout
pub fn timeout(
  account account: Account,
  timeout timeout: Option(Int),
) -> Account {
  let new_timeout = case timeout {
    None -> None
    Some(timeout_ms) if timeout_ms > 0 -> Some(timeout_ms)
    Some(_) -> account.timeout
  }
  Account(..account, timeout: new_timeout)
}

/// Set an account's optional interval
pub fn interval(
  account account: Account,
  interval interval: Option(Int),
) -> Account {
  let new_interval = case interval {
    None -> None
    Some(interval_ms) if interval_ms > 0 -> Some(interval_ms)
    Some(_) -> account.interval
  }
  Account(..account, interval: new_interval)
}

pub fn get_address(account account: Account) -> Address {
  account.address
}

pub fn get_interval(account account: Account) -> Option(Int) {
  account.interval
}

pub fn get_timeout(account account: Account) -> Option(Int) {
  account.timeout
}
