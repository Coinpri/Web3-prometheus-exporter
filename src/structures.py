import json
from pydantic import BaseModel 
from typing import List, Dict, Any


class Blockchain(BaseModel):
    name: str
    rpc_url: str

class Balance(BaseModel):
    name: str
    value: int
    extra_labels: Dict[str, str] = {}
    def get_labels(self) -> Dict[str, str]:
        return {"name": self.name, "value": self.value} | self.extra_labels

class Account(BaseModel):
    address: str
    name: str
    balances: List[Balance] = []
    extra_args: Any = None

class Asset(BaseModel):
    id: str
    blockchain: Blockchain
    module: str
    name: str
    decimals: int
    accounts: List[Account]
    extra_parameters: Dict[Any, Any] = {}