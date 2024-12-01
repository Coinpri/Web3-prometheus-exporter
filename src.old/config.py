import yaml
from structures import *
from typing import List
import os

class Config:
    _instance = None
    assets = List[Asset]

    # Default configs
    port = 8990
    bind_addr = "0.0.0.0"
    query_timeout = 60

    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super(Config, cls).__new__(cls)
            cls._instance.__initialized = False
        return cls._instance

    def __init__(self, config_file='config.yaml'):
        if self.__initialized:
            return
        self.config_file = config_file
        self.data = self.load_config()
        self.__initialized = True

    def load_config(self):
        with open(self.config_file, 'r') as file:
            yaml_data = yaml.safe_load(file)
            assets_data = yaml_data.get('assets', [])
            self.assets = [Asset.parse_obj(asset) for asset in assets_data]
            self.port = int(os.getenv('WEB3_PROMETHEUS_EXPORTER_PORT', self.port))
            self.bind_addr = os.getenv('WEB3_PROMETHEUS_EXPORTER_BIND_ADDR', self.bind_addr)
            self.query_timeout = int(os.getenv('WEB3_PROMETHEUS_EXPORTER_QUERY_TIMEOUT', self.query_timeout))