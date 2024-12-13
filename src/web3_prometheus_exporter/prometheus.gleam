import gleam/dict.{type Dict}

pub type Message {
  UpdateBalance(new_balance: Int, labels: Dict(String, String))
}
