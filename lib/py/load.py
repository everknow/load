#!/usr/bin/env python3

import sys
import os
import time
import fcntl
import selectors

QUEUE=b'\x01'
SID=QUEUE
GEN=b'\x05'
  
def encode(data):
  return ((len(data)).to_bytes(2, byteorder='big')+data)

def decode(data):
  l = int.from_bytes(data[:2],'big')
  return data[2:l+2]

def send(data):
  with os.fdopen(sys.stdout.fileno(), "wb", closefd=False) as stdout:
    stdout.write(QUEUE+SID+encode(data))
    stdout.flush()

def read():
  return sys.stdin.buffer.read()

def cycle(nonce, f):
  global buf
  while True:
    time.sleep(1)
    buf = input().encode('utf-8')
    if len(buf) > 1 and buf[:1] == GEN:
      for i in list(range(nonce,nonce+buf[1])):
        f(i)
        time.sleep(2)
      nonce = nonce+buf[1]

def main():
  cycle(50, lambda i:send(f"sending tx{i}".encode('utf-8')))
  # if len(sys.argv) >1 and sys.argv[1] == "writer":

# main()