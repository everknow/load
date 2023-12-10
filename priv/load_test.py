#!/usr/bin/env python3

import chain

def main():
  base = chain.base()
  accounts_quantity = 1
  tx1 = lambda s: chain.bank_send_tx(s['sender'], s['funder_phrase'], f"1000{s['denom']}")
  tx2 = lambda s: chain.bank_send_tx(s['funder_phrase'], s['sender'], f"1000{s['denom']}")
  execution_plan = lambda accounts: [
    (base | {'switch_at': 5} | accounts[0], [tx1, tx2])
  ]
  chain.cycle(base, execution_plan, accounts_quantity, f"1000000000{base['denom']}")

main()