def encode(data):
  return ((len(data)).to_bytes(2, byteorder='big')+data)
def decode(data):
  l = int.from_bytes(data[:2],'big')
  return data[2:l+2]