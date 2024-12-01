from web3 import Web3
from structures import Balance, Account
from typing import List, Dict, Any
import json

erc20_abi = json.loads('[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"payable":false,"type":"function"}]')
def get_extra_label_names():
    return ['contract_address']

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance]:
    contract_address = extra_parameters['contract_address']
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    if not web3.is_connected():
        raise Exception(f"Cannot connect to RPC {rpc_url}")

    contract = web3.eth.contract(address=contract_address, abi=erc20_abi)

    balance = contract.functions.balanceOf(account.address).call()

    balances = [Balance(name=f"erc20", value=balance, extra_labels={'contract_address': contract_address})]
    return balances