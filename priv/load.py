#!/usr/bin/env python3

import sys
import os
import time
import functools
import base64

QUEUE=b'\x01'
MASTER=b'\x02'
GEN=b'\x05'
API=b'\x06'
CREATE_ACCOUNTS=b'\x07'
  
def encode(data):
  return ((len(data)).to_bytes(2, byteorder='big')+data)

def decode(data):
  l = int.from_bytes(data[:2],'big')
  return (data[2:l+2], data[l+2:])

def send(args):
  (data, s) = args
  with os.fdopen(sys.stdout.fileno(), "wb", closefd=False) as stdout:
    dest = s.get('dest', QUEUE)
    r = s.get('routing', ["", "", ""])
    sid = s.get('account_number', 0)
    fee_denom = s.get('denom')
    # out={'dest': dest, 'sid': sid.to_bytes(1, byteorder='big'), 'routing': r, 'fee_denom': fee_denom, 'data': data}
    # print(f"[load.send] sending: {out}", file=sys.stderr, end = "\n\r")
    # print(f"[load.send] s: {s}", file=sys.stderr, end = "\n\r")
    stdout.write(dest+sid.to_bytes(1, byteorder='big')+functools.reduce(lambda a,x:a+encode(x.encode('utf-8')), r, b'')+encode(fee_denom.encode('utf-8'))+encode(data))
    stdout.flush()
  return s

def read():
  return sys.stdin.buffer.read()

def cycle(master_s, f_tx_plan, f, f2):
  global buf
  tx_plan=None
  while True:
    time.sleep(1)
    buf = input().encode('utf-8')
    if len(buf) > 1:
      if buf[:1] == GEN:
        tx_plan = functools.reduce(lambda a,_: gen(f,a), range(0,buf[1]), tx_plan)
      elif buf[:1] == API:
        [wpid, pid, key, arg0, tx] = buf[1:].decode('utf-8').split('#')
        master_s = f(base64.b64decode(tx), master_s | {'routing': [wpid, pid, key], 'denom': arg0})
        master_s.pop('routing', None)
      elif buf[:1] == CREATE_ACCOUNTS:
        tx_plan = prepare(f_tx_plan(f2()))

def gen(f, tx_plan):
  # print(f"[load.gen] tx_plan: {tx_plan}", file=sys.stderr, end = "\n\r")
  (acc_s, txs) = tx_plan[0]
  acc_s = f(txs[0], acc_s)
  return tx_plan[1:]+[(acc_s, strategy(acc_s, txs))]

def strategy(acc_s, txs):
  if 'switch_at' in acc_s and acc_s['sequence'] % acc_s['switch_at'] == 0:
    return txs[1:]+[txs[0]]
  else:
    return txs

def prepare(tx_plan):
  return [(s,[tx(s) for tx in txs]) for (s,txs) in tx_plan]