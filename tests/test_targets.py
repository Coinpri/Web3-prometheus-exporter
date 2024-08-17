import pytest
import importlib
import os
import inspect
from typing import List, Dict, Any
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../src')))

from structures import Balance, Account

# Directory where the target modules are located
TARGETS_DIR = 'src/targets'

def get_modules_in_directory(directory):
    modules = []
    for file in os.listdir(directory):
        if file.endswith(".py") and file != "__init__.py":
            module_name = file[:-3]  # Strip the '.py' extension
            modules.append(f"{directory.replace('/', '.')}.{module_name}")
    return modules

@pytest.mark.parametrize("module_name", get_modules_in_directory(TARGETS_DIR))
def test_get_balance_function(module_name):
    module = importlib.import_module(module_name)
    
    # Check if the module has a function named get_balance
    assert hasattr(module, 'get_balance'), f"Module {module_name} does not have a 'get_balance' function"
    
    # Get the get_balance function
    get_balance = getattr(module, 'get_balance')
    
    # Check if get_balance is callable
    assert callable(get_balance), f"'get_balance' in {module_name} is not callable"
    
    # Get the signature of the get_balance function
    signature = inspect.signature(get_balance)
    
    # Check the parameters of the function
    parameters = list(signature.parameters.values())
    assert len(parameters) == 3, f"'get_balance' in {module_name} should have exactly 2 parameters"
    assert parameters[0].annotation == str, f"The first parameter of 'get_balance' in {module_name} should be of type 'str'"
    assert parameters[1].annotation == Account, f"The second parameter of 'get_balance' in {module_name} should be of type 'Account'"
    assert parameters[2].annotation == Dict[Any, Any], f"The third parameter of 'get_balance' in {module_name} should be of type 'Dict[Any, Any]'"
    
    # Check the return type of the function
    assert signature.return_annotation == List[Balance], f"'get_balance' in {module_name} should return a 'List[Balance]'"

