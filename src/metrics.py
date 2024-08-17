import importlib
from prometheus_client import start_http_server as start_server
from prometheus_client import Gauge
from config import Config
from structures import *

gauges = {}
config = Config()
common_labels = [
    "asset_id",
    "asset_name",
    "blockchain_name",
    "rpc_url",
    "balance_name",
    "account",
    "address",
    "decimals",
    "module"
]

def start_http_server():
    start_server(config.port, addr=config.bind_addr)

def create_metrics(assets):
    for asset in assets:
        gauge_name = get_metric_name(asset.id)
        gauge_description = f"{asset.name} asset balance on {asset.blockchain.name}"
        module = importlib.import_module(f'targets.{asset.module}')
        if hasattr(module, 'get_extra_label_names'):
            extra_label_names = module.get_extra_label_names()
        else:
            extra_label_names = []
        create_gauge(gauge_name, gauge_description, extra_label_names)


def create_gauge(gauge_name, gauge_description, extra_label_names):
    labels = common_labels + extra_label_names
    gauges[gauge_name] = Gauge(gauge_name, gauge_description, labels)

def set_gauge(gauge_name, new_value, gauge_labels):
    gauges[gauge_name].labels(**gauge_labels).set(new_value)

def update_metrics(assets):
    for asset in assets:
        labels = {}
        labels['asset_id'] = asset.id
        labels['asset_name'] = asset.name
        labels['blockchain_name'] = asset.blockchain.name
        labels['rpc_url'] = asset.blockchain.rpc_url
        labels['decimals'] = asset.decimals
        labels['module'] = asset.module
        gauge_name = get_metric_name(asset.id)
        for account_index, account in enumerate(asset.accounts):
            labels['account'] = account.name
            labels['address'] = account.address
            print(account, flush=True)
            for balance in account.balances:
                print(balance, flush=True)
                labels['balance_name'] = balance.name
                labels = labels | balance.extra_labels
                set_gauge(gauge_name, balance.value, labels)


def get_metric_name(asset_id):
    return f"web3_prometheus_exporter_{asset_id}_account_balance"
