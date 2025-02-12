import glaml
import gleam/option.{type Option, None, Some}
import gleam/result
import snag.{type Result}

/// Returns the string contained in a DocNode
/// If the DocNode is not a string, returns an error
pub fn to_string(node: glaml.Node) -> Result(String) {
  case node {
    glaml.NodeStr(val) -> Ok(val)
    _ -> snag.error("field is not a string")
  }
}

/// Returns the Int contained in a DocNode
/// If the DocNode is not an Int, returns an error
pub fn to_int(node: glaml.Node) -> Result(Int) {
  case node {
    glaml.NodeInt(val) -> Ok(val)
    _ -> snag.error("field is not an Int")
  }
}

/// Returns the sequence (list) contained in a DocNode
/// If the DocNode is not a sequence, returns an error
pub fn to_seq(node: glaml.Node) -> Result(List(glaml.Node)) {
  case node {
    glaml.NodeSeq(val) -> Ok(val)
    _ -> snag.error("field is not a seqence (list)")
  }
}

/// Attempts to `glaml.sugar` a node name to a `glaml.Node`
/// And checking the type of the node (use `to_string`, `to_int`, `to_seq`)
/// Running the `apply` function if Ok, otherwise returning the error
pub fn try_parse(
  node: glaml.Node,
  field: String,
  transform: fn(glaml.Node) -> Result(b),
  apply: fn(b) -> Result(c),
) -> Result(c) {
  let r =
    glaml.select_sugar(node, field)
    |> result.replace_error(snag.new(
      "could not parse field \"" <> field <> "\"",
    ))
  let s = result.try(r, transform)
  result.try(s, apply)
}

/// Helper function to extract the option `interval` and `timeout`
/// ms fields that can be found in blockchain, asset, or account configs.
pub fn extract_optional_times(node: glaml.Node) -> #(Option(Int), Option(Int)) {
  let interval = case glaml.select_sugar(node, "interval") {
    Ok(glaml.NodeInt(interval)) -> Some(interval)
    _ -> None
  }
  let timeout = case glaml.select_sugar(node, "timeout") {
    Ok(glaml.NodeInt(timeout)) -> Some(timeout)
    _ -> None
  }
  #(interval, timeout)
}
