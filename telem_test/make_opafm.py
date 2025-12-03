#!/usr/bin/env python3

# REQUIRES 2 args:
#  1. The csv file where the settings are stored
#  2. The index of the setting to be applied

import os
import os.path as op
import sys
# import pandas as pd
import openpyxl
import xml
import .experiment_map

if __name__=="__main__":
    exp_file = sys.argv[1]
    # idx = sys.argv[2]
    with open(exp_file, 'r') as f:
        expm=f.readlines()
        var_names = expm[0].split(',')
        for x in expm[1:]:
            xint=[int(k) for k in x.split(',')]
            exp_dict=dict(zip(var_names,xint))
            experiment_map(exp_dict)
            
    # READ the header and the index of the file.
    # var_names = header of exp_file
    # var_vals = index of exp_file


    ## Experiment map should return a dict with the name of the key and their values for this selection.
