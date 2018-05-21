#!/bin/python
import fuzzy as f
import argparse
import os

def main(args=None):
    dmeta = f.DMetaphone()
    output = dmeta( args.w )
    print output

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("-w", help="Give me a word")
    args = parser.parse_args()
    main(args)

