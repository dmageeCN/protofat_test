#!/usr/bin/env python3

# PROVIDE THE RELATIVE PATH TO THE CSV FILE
import os
import os.path as op
import sys
import pandas as pd
from scipy.stats import gmean

if __name__=="__main__":

    thispath=op.dirname(op.realpath(__file__))
    csvpath=op.join(thispath,op.sys.argv[1])
    df1=pd.read_csv(csvpath)
    df1.set_index('Size',inplace=True)
    summarydf=pd.DataFrame(df1.mean())
    summarydf.columns=['mean']
    summarydf['max']=df1.max()
    summarydf['geomean']=gmean(df1)
    summarydf['sum']=df1.sum()
    finalsummary=summarydf.describe()
    finals=finalsummary.T
    finals['std_dev_ratio']=(finalsummary.T['std']/finalsummary.T['mean']*100)
    finalsummary=finals.T

    newcsv = "-".join(csvpath.split('-')[:-1])
    newcsv += "extrasummary.csv"
    print(csvpath)
    print(newcsv)

    finalsummary.to_csv(newcsv, float_format='%.2f')