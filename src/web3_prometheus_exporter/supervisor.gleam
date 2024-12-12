import chip
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/erlang_supervisor as erlsup
import gleam/result
import gleam/uri

pub type Group {
  Group(blockchain_name: String, asset_name: Option(String))
}
