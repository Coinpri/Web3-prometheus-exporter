import requests
from structures import Balance, Account
from typing import List, Dict, Any

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance] :
    headers = {
        'Content-Type': 'application/json',
    }

    payload = {
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [account.address, "latest"],
        "id": 1,
    }

    response = requests.post(rpc_url, json=payload, headers=headers)
    response.raise_for_status() 
    result = response.json()

    if "result" in result:
        balance_wei = int(result["result"], 16)
        balances = [
            Balance(name="native", value=balance_wei)
        ]
        return balances
    else:
        raise Exception("Error in response: " + str(result))