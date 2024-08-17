from structures import Balance, Account
from typing import List, Dict, Any


# This function is optional. It allows you to declare arbitrary labels for the balances of your asset.
# If you do not need extra custom labels, you can omit this function.
def get_extra_label_names():
    return ['arbitrary_label_for_prometheus_metric']

# This function MUST be declared and MUST have its arguments typed as shown below.
# The `rpc_url` will contain the string from the asset's `blockchain.rpc_url` field in the `config.yaml` file.
# The `account` will contain all the fields and optional custom subfields of the `accounts` of the configured asset. See the `structues.py` file for more details on the Accounts fields.
def get_balance(rpc_url: str, account: Account, extra_parameters: Dict[Any,Any]) -> List[Balance]:


    # You must return an array of "Balance"s.
    # Most assets will only have a single Balance, but some might have multiple
    # For example, the `native_substrate` has 3 Balances which match the 3 default balances returned by a substrate chain : "frozen", "free" and "reserved".
    # The balances WILL be added together in the Grafana dashboard to display a final, total balance. Make sure the rewards you return make sense to be added together.
    balances = [
        Balance(name="rewards_pending", value=420, extra_labels={'arbitrary_label_for_prometheus_metric': 'foobar'}), # The keys of the `extra_labels` argument must match those returned by the `get_extra_label_names` function.
        Balance(name="rewards_collected", value=69, extra_labels={'arbitrary_label_for_prometheus_metric': 'barfoo'})
    ]
    return balances