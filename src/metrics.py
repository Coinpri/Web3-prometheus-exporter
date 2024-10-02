import importlib
from prometheus_client import start_http_server as start_server
from prometheus_client import Gauge
from config import Config
from structures import *

gauges = {}
config = Config()
balance_metric_common_labels = [
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

validator_status_metric_common_labels = [
    "asset_id",
    "asset_name", 
    "blockchain_name",
    "rpc_url",
    "account",
    "address",
    "module",
    "status"
]

def start_http_server():
    start_server(config.port, addr=config.bind_addr)

def create_metrics(assets):
    for asset in assets:
        # Create balance gauges
        gauge_name = get_account_balance_metric_name(asset.id)
        gauge_description = f"{asset.name} asset balance on {asset.blockchain.name}"
        module = importlib.import_module(f'targets.{asset.module}')
        if hasattr(module, 'get_extra_label_names'):
            extra_label_names = module.get_extra_label_names()
        else:
            extra_label_names = []
        all_labels = balance_metric_common_labels + extra_label_names
        create_gauge(gauge_name, gauge_description, all_labels)
        
    # Create validator uptime gauges
    gauge_name = f"web3_prometheus_exporter_validator_status"
    gauge_description = f"validator status metric for all declared validators"
    create_gauge(gauge_name, gauge_description, validator_status_metric_common_labels)
        



def create_gauge(gauge_name, gauge_description, label_names):
    gauges[gauge_name] = Gauge(gauge_name, gauge_description, label_names)

def set_gauge(gauge_name, new_value, gauge_labels):
    gauges[gauge_name].labels(**gauge_labels).set(new_value)

def update_metrics(assets):
    for asset in assets:
        account_balance_metric_labels = {}
        account_balance_metric_labels['asset_id'] = asset.id
        account_balance_metric_labels['asset_name'] = asset.name
        account_balance_metric_labels['blockchain_name'] = asset.blockchain.name
        account_balance_metric_labels['rpc_url'] = asset.blockchain.rpc_url
        account_balance_metric_labels['decimals'] = asset.decimals
        account_balance_metric_labels['module'] = asset.module
        gauge_name = get_account_balance_metric_name(asset.id)
        validator_status_gauge_name = "web3_prometheus_exporter_validator_status"
        for account_index, account in enumerate(asset.accounts):
            account_balance_metric_labels['account'] = account.name
            account_balance_metric_labels['address'] = account.address
            print(account, flush=True)
            # Set balance metrics for all accounts
            for balance in account.balances:
                print(balance, flush=True)
                account_balance_metric_labels['balance_name'] = balance.name
                account_balance_metric_labels = account_balance_metric_labels | balance.extra_labels
                print(account_balance_metric_labels, flush=True)
                set_gauge(gauge_name, balance.value, account_balance_metric_labels)
            # If the account is a validator, set its validator status metric
            if account.is_validator:
                validator_status_metric_labels = account_balance_metric_labels.copy()
                del validator_status_metric_labels['decimals']
                del validator_status_metric_labels['balance_name']
                # remove labels unneeded for validator metric
                for status_name, is_active_status in account.validator_statuses.items():
                    validator_status_metric_labels["status"] = status_name
                    print(validator_status_metric_labels, flush=True)
                    value = 0
                    if is_active_status:
                        value = 1
                    set_gauge(validator_status_gauge_name, value, validator_status_metric_labels)


def get_account_balance_metric_name(asset_id: str):
    return f"web3_prometheus_exporter_{asset_id}_account_balance"
