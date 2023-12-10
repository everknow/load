#!/usr/bin/env python3

import os
import protoss
from pb import tx_body, any
import load
import re
import sys
import cosmos.bank.v1beta1.tx_pb2

def base():
  funder_phrase = os.getenv("FUNDER_PHRASE")
  addr_prefix = os.getenv("ADDR_PREFIX")
  return {
    'addr_prefix': addr_prefix,
    'fee_amount': "500000",
    'denom': os.getenv("DENOM"),
    'chain_id': os.getenv("CHAIN_ID"),
    'gas_price': 100000000000,
    'funder_phrase': funder_phrase,
    'funder_address': protoss.phrase_address(funder_phrase, addr_prefix),
    'url': "http://"+os.getenv("CHAIN_HOST")
  }

def bank_send_tx(from_address, to_address, coins):
  return tx_body([
    any(
      "/cosmos.bank.v1beta1.MsgSend",
      cosmos.bank.v1beta1.tx_pb2.MsgSend(
        from_address = from_address,
        to_address = to_address,
        amount = [coin(coinstr) for coinstr in coins]
      )
    )
  ])

def coin(coinstr):
  s = re.search(r"(\d+)(\w+)", coinstr)
  return cosmos.base.v1beta1.coin_pb2.Coin(amount = s.group(1), denom = s.group(2))

def create_accounts(addr_prefix, quantity, funder_phrase, funder_address, coins):
  print(coins, file=sys.stderr, end = "\n\r")
  accounts = [protoss.new_account(addr_prefix) for _ in range(quantity)]
  for account in accounts:
    address = account['address']
    for coinstr in coins:
      load.send((bank_send_tx(funder_address, address, [coinstr]), {'dest': load.MASTER, 'routing': [address], 'denom': coin(coinstr).denom}))
  return accounts

def f(tx, s, url):
  if not protoss.has_account_info(s):
    s = s | protoss.get_account_info(s['address'], url)
  return load.send(protoss.sign_tx(tx , s))

def cycle(base, execution_plan, accounts_quantity, *coins):
  load.cycle(
    base | protoss.phrase_account(base['funder_phrase'], base['addr_prefix']),
    execution_plan,
    lambda tx, s: f(tx, s, base['url']),
    lambda : create_accounts(base['addr_prefix'], accounts_quantity, base['funder_phrase'], base['funder_address'], coins)
  )