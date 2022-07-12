
import math
import sys
import argparse

def main(args):
    fee = (0.9/(1.25+math.e**(int(args)/75000)))+0.01
    adjusted64x64 = fee *2** 64
    return adjusted64x64


if __name__ == '__main__':
    args = sys.argv
    main(args[1])