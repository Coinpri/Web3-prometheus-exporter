import gleam/dict.{type Dict}
import gleam/result
import snag.{type Result}

pub fn try_get(
  from: Dict(key, value),
  key: key,
  then: fn(key, value) -> Result(a),
) -> Result(a) {
  result.try(
    dict.get(from, key)
      |> result.replace_error(snag.new("failed to find key \"asset\"")),
    fn(value) { then(key, value) },
  )
}
