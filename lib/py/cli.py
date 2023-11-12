import requests
import os

load_host = os.getenv("LOAD_HOST", "127.0.0.1")

def config():  
  res = requests.post(f"http://{load_host}:8888/config", json = {"common": {
    "hit_host": os.getenv("CHAIN_HOST", "127.0.0.1"),
    "hit_port": os.getenv("RPC_PORT", 26657)},
    "connect_hosts": [load_host],
    "gen": {
      "os_command": os.getenv("OS_COMMAND", "python3 examples/load_test.py"),
      "os_dir": os.getenv("OS_DIR"),
      "os_env": {
        "ADDR_PREFIX": os.getenv("ADDR_PREFIX"),
        "CHAIN_HOST": os.getenv("CHAIN_HOST", "127.0.0.1"),
        "CHAIN_ID": os.getenv("CHAIN_ID"),
        "DENOM": os.getenv("DENOM"),
        "FUNDER_PHRASE": os.getenv("FUNDER_PHRASE"),
        "LD_LIBRARY_PATH": os.getenv("LD_LIBRARY_PATH"),
        "PYTHONPATH": os.getenv("PYTHONPATH"),
        "PYTHONPYCACHEPREFIX": ".cache"
        }
      },
    "poller": {
      "content_decode": "from_base64", "content_selector": ["block", "data", "txs"], "group": "pollers",
      "port": os.getenv("REST_PORT", 1317),
      "pos_decode": "from_dec", "pos_from": "latest", "pos_selector": ["block", "header", "height"], "pos_to": 1,
      "statement": "get /cosmos/base/tendermint/v1beta1/blocks/X XPOSX X"
      },
    "serializer": {
      "pos_selector": ["result", "hash"], "protocol": "http", "statement": "post /"
      }
    })
  
  print(res)

def start():
  res = requests.post(f"http://{load_host}:8888/start", json =  {
    "scale_function": "uniform", "scale_growth_coefficient": 0.1, "scale_height": 1,
    "scale_tick_interval": 1, "scale_tick_timeunit": "seconds", "scale_width": 2, 
    "stats_tick_interval": 1, "stats_tick_timeunit": "seconds",
    "test_duration_interval": 40, "test_duration_timeunit": "seconds"
    })
  
  print(res)