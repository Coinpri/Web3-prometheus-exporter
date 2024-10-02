import requests
from structures import Balance, Account
from typing import List, Dict, Any
import bech32
import hashlib
import base64


possible_validator_statuses = [
    "up",
    "down"
]

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance] :
    

    query_url = f"cosmos/bank/v1beta1/balances/{ account.address }"
    result = query_cosmos_rpc(rpc_url, query_url)

    if "balances" in result:
        # balance_decimal = int(result["balances"][0]['amount'])
        balances = []
        for balance_data in result['balances']:
            new_balance = Balance(name=balance_data['denom'], value=balance_data['amount'])
            balances.append(new_balance)
        return balances
    else:
        raise Exception("Error in response: " + str(result))



def check_validator_status(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> Dict[str,bool] :
    
    window_block_missed_threshold = extra_parameters.get("validator", {}).get("window_block_missed_threshold", 0)
    validator_status = is_validator_up(rpc_url, account.address, window_block_missed_threshold)

    result = dict.fromkeys(possible_validator_statuses, False)
    result["up"] = validator_status
    result["down"] = not validator_status

    return result


def is_validator_up(rpc_url: str, address: str, window_block_missed_threshold: int) -> bool:
    valcons_address = get_valcons_address_from_wallet_address(address, rpc_url)

    url = f"cosmos/slashing/v1beta1/signing_infos/{valcons_address}"
    result = query_cosmos_rpc(rpc_url, url)
    block_missed = result['val_signing_info']['missed_blocks_counter']
    if block_missed > window_block_missed_threshold:
        return False
    return True


def get_valcons_address_from_wallet_address(address: str, rpc_url: str) -> str:
    wallet_prefix = address.split('1')[0]
    oper_prefix = wallet_prefix + "valoper"
    valcons_prefix = wallet_prefix + "valcons"
    # Decode the Bech32 address
    hrp, data = bech32.bech32_decode(address)
    
    # Check if the prefix matches the old prefix
    if hrp != wallet_prefix:
        raise ValueError(f"Address prefix does not match the old prefix: {hrp} =/= {wallet_prefix}")
    
    # Re-encode the address using the new prefix
    oper_address = bech32.bech32_encode(oper_prefix, data)

    query_url = f"cosmos/staking/v1beta1/validators/{oper_address}"
    result = query_cosmos_rpc(rpc_url, query_url)
    cosmos_b64_pubkey = None
    if "validator" in result:
        if "consensus_pubkey" in result['validator']:
            if "key" in result['validator']['consensus_pubkey']:
                cosmos_b64_pubkey = result['validator']['consensus_pubkey']['key']
    
    if not cosmos_b64_pubkey:
        raise Exception("Error in response, missing validator.consensus_pubkey.key item: " + str(result))
    
    cosmos_pubkey_bytes = base64.b64decode(cosmos_b64_pubkey)
    hashed_key = hashlib.sha256(cosmos_pubkey_bytes).digest()
    sliced_key = hashed_key[:20]
    converted_key = bech32.convertbits(sliced_key, 8, 5, pad=True)
    valcons_address = bech32.bech32_encode(valcons_prefix, converted_key)
    return valcons_address



def query_cosmos_rpc(rpc_url: str, query_url: str) -> Dict:
    headers = {
        'Content-Type': 'application/json',
    }
    url = f"{rpc_url}{query_url}"

    response = requests.get(url, headers=headers)
    response.raise_for_status()  # Raise an error for bad status codes
    result = response.json()
    return result