from substrateinterface import SubstrateInterface
from structures import Balance, Account
from typing import List, Dict, Any

def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance] :
    headers = {
        'Content-Type': 'application/json',
    }


    # Initialize connection to a Polkadot node
    substrate = SubstrateInterface(
        url=rpc_url,  # Use the appropriate node URL
        # type_registry_preset='default'
    )

    account_data = substrate.query('System', 'Account', [account.address])

    free_unfrozen_balance = account_data.value['data']['free'] - account_data.value['data']['frozen']       # "Frozen" balance counts as "free". We want all the balances together to cumulate to the actual total balance,
                                                                                                            # but we can't just add "free" and "frozen" together for that reason. We're instead reporting the "free-unfrozen" balance.
    reserved_balance = account_data.value['data']['reserved']
    frozen_balance = account_data.value['data']['frozen']

    balances = [
        Balance(name='free-unfrozen', value=free_unfrozen_balance),
        Balance(name='reserved', value=reserved_balance),
        Balance(name='frozen', value=frozen_balance)
    ]
    return balances