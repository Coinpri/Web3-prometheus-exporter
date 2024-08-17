from web3 import Web3
from structures import Balance, Account
from typing import List, Dict, Any
import json

erc721_abi = json.loads('[{"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"index","type":"uint256"}],"name":"tokenOfOwnerByIndex","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}]')

def get_extra_label_names():
    return ['contract_address', 'token_id']

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance]:
    contract_address = extra_parameters['contract_address']
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    if not web3.is_connected():
        raise Exception(f"Cannot connect to RPC {rpc_url}")

    contract = web3.eth.contract(address=contract_address, abi=erc721_abi)

    balance = contract.functions.balanceOf(account.address).call()

    balances = []
    for i in range(balance):
        token_id = contract.functions.tokenOfOwnerByIndex(account.address, i).call()
        balances.append(Balance(name=f"nft_{token_id}", value=1, extra_labels={'contract_address': contract_address, 'token_id': str(token_id)}))
    return balances