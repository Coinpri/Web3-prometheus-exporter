import requests
from structures import Balance, Account
from typing import List, Dict, Any

possible_validator_statuses = [
    "up",
    "down"
]

def check_validator_status(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> Dict[str,bool] :
    validator_status = is_validator_up(account.address)
    result = dict.fromkeys(possible_validator_statuses, False)
    result["up"] = validator_status
    result["down"] = not validator_status
    return result

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance] :
    headers = {
        'Content-Type': 'application/json',
    }

    url_path = f"cosmos/bank/v1beta1/balances/{ account.address }"
    full_url = rpc_url + url_path

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()  # Raise an error for bad status codes
    result = response.json()
    if "balances" in result:
        # balance_decimal = int(result["balances"][0]['amount'])
        balances = []
        for balance_data in result['balances']:
            new_balance = Balance(name=balance_data['denom'], value=balance_data['amount'])
            balances.append(new_balance)
        return balances
    else:
        raise Exception("Error in response: " + str(result))

def is_validator_up(address: str) -> bool:
    if address == "cosmos1z8zjv3lntpwxua0rtpvgrcwl0nm0tltgyuy0nd":
        return True
    return False