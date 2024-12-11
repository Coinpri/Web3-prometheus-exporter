import glaml
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import snag.{type Result}

import web3_prometheus_exporter/util/glaml as glaml_util

import eth_crypto/eth.{type Address, type SmartContract}
