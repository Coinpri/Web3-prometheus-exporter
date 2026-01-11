from web3_prometheus_exporter.config import Config
from web3_prometheus_exporter.metrics import start_http_server, create_metrics, update_metrics
from web3_prometheus_exporter.structures import *
from web3_prometheus_exporter.query import query_balances
import time
import sys

def main():
    if len(sys.argv) < 2:
        config_file_path = "config.yml"
    else:
        config_file_path = sys.argv[1]

    config = Config(config_file=config_file_path)
    assets = config.assets
    start_http_server()

    create_metrics(assets)
    while True:
        query_balances(assets)
        update_metrics(assets)

        time.sleep(config.query_timeout)


if __name__ == "__main__":
    main()
