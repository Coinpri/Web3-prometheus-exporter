import glaml
import snag.{type Result}

pub fn glaml_node_to_string(node: glaml.DocNode) -> Result(String) {
  case node {
    glaml.DocNodeStr(val) -> Ok(val)
    _ -> snag.error("name field is not a string")
  }
}
