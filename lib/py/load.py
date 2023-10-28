#!/usr/bin/env python3

import sys
import os

QUEUE=b'\x01'
SID=QUEUE
  
def encode(data):
  return ((len(data)).to_bytes(2, byteorder='big')+data)

def decode(data):
  l = int.from_bytes(data[:2],'big')
  return data[2:l+2]

def send(data):
  with os.fdopen(sys.stdout.fileno(), "wb", closefd=False) as stdout:
    stdout.write(QUEUE+SID+encode(data))
    stdout.flush()
