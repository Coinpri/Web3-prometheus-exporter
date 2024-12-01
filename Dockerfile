FROM ghcr.io/gleam-lang/gleam:v1.6.2-erlang-alpine as build
WORKDIR /app
COPY gleam.toml .
COPY manifest.toml .
COPY test test
COPY src src

RUN gleam deps download
RUN gleam test
RUN gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:v1.6.2-erlang-alpine as run

COPY --from=build /app/build/erlang-shipment /app

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]