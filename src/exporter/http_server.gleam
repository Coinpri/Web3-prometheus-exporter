import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result
import mist.{type Connection, type ResponseData}

import exporter/prometheus

pub fn start_server(port: Int, bind: String) -> Result(Nil, Nil) {
  mist.new(metrics_endpoint_handler)
  |> mist.port(port)
  |> mist.bind(bind)
  |> mist.start_http
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}

fn metrics_endpoint_handler(
  _request: Request(Connection),
) -> Response(ResponseData) {
  let response_data =
    prometheus.export_metrics()
    |> bytes_tree.from_string
    |> mist.Bytes
  response.new(200)
  |> response.set_body(response_data)
}
