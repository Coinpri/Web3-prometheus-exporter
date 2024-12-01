import importlib
from structures import *
from typing import List
import time

def query_balances(assets: List[Asset]):
    results = {}
    for asset in assets:
        module = importlib.import_module(f'targets.{asset.module}')
        # Fetching all balances for all accounts
        for account in asset.accounts:
            account.balances = module.get_balance(asset.blockchain.rpc_url, account, asset.extra_parameters)
            time.sleep(1)   # 1 second sleep to avoid rate limit on public endpoints
            # Fetching uptime if the account is a validator
            if account.is_validator :
                account.validator_statuses = module.check_validator_status(asset.blockchain.rpc_url, account, asset.extra_parameters)
                time.sleep(1)