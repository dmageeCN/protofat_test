#!/usr/bin/env python3

import pandas as pd
import json
import sys
import os


def write_gpc_csv(ofile, df, key, keytop=None):
    tbl_title = ""
    hdr=False
    if keytop:
        tbl_title = f"\n{keytop.upper()}\n"
        hdr=True

    tbl_title += "_".join(key.replace('('," ").replace(")", " ").split())
    with open(ofile, 'a') as f:
        f.write(f"{tbl_title}\n")
        df.to_csv(f, header=hdr)

def main(json_file):
    if not os.path.isfile(json_file):
        print(f"Argument {json_file} is not a file")
        sys.exit(0)
    
    rslt_dir  = os.path.dirname(os.path.realpath(json_file))
    json_base = os.path.basename(json_file)
    
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    outfile = os.path.join(rslt_dir, json_base.split('.')[0]+'.csv')

    meta_dict = data.pop('test_info')
    metadata  = pd.Series(meta_dict, name="metadata").str.replace(',',';')
    metadata.to_csv(outfile, mode='w')
    for key, val in data.items():
        for i, (k, v) in enumerate(val.items()):
            rslt_df = pd.DataFrame(v).T
            if i == 0:
                write_gpc_csv(outfile, rslt_df, k, key)
            else:
                write_gpc_csv(outfile, rslt_df, k)


if __name__ == '__main__':
    main(sys.argv[1])