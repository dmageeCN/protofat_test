#!/usr/bin/env python3

# REQUIRES 2 args:
#  1. The csv file where the settings are stored
#  2. The index of the setting to be applied

import os
import os.path as op
import sys
import xml.etree.ElementTree as ET

OPA_RESET_DIR    = op.join(op.expanduser('~'), ".restart_FM")
OPA_RESET_SIGNAL = op.join(OPA_RESET_DIR, "restart_file")

SCALINGCOORD = { "EXP" : {
                    "HIGH": "500,502,505,511,521,535,554,579,612,651,699,756,823,900",
                    "LOW" : "100,102,105,111,121,135,154,179,212,251,299,356,423,500",
                    "FULL": "100,103,110,122,141,169,208,258,323,402,498,612,746,900" },
                 "LOG" : {
                    "HIGH": "500,594,654,698,733,762,787,809,828,845,861,875,888,900",
                    "LOW" : "100,194,254,298,333,362,387,409,428,445,461,475,488,500",
                    "FULL": "100,287,407,495,566,624,673,717,755,789,821,850,876,900" },
                 "LIN" : {
                    "HIGH": "500,530,561,592,623,653,684,715,746,776,807,838,869,900",
                    "LOW" : "100,130,161,192,223,253,284,315,346,376,407,438,469,500",
                    "FULL": "100,161,223,284,346,407,469,530,592,653,715,776,838,900" }
    }

CDIST  = ["EXP", "LOG", "LIN"]
CRANGE = ["HIGH", "LOW", "FULL"]

# OPAFM='/etc/opa-fm/opafm.xml'
# Put it in the tmp folder
# JUST MAKE SURE THERE'S an OPAFM_ORIG.xml
OPAFM=op.join(OPA_RESET_DIR, "opafm_replace.xml")
OPABASE=op.join(OPA_RESET_DIR, "opafm_base.xml")

# TAKES THE VALUES AND ELEMENTS AND MODIFIES XML
def modify_xml(mod_dict):
    tr=ET.parse(OPABASE)
    root=tr.getroot()
    for element, val in mod_dict:
        elem = root.find(".//"+element)
        elem.text = val

    tr.write(OPAFM)

# Creates values to update xml
def experiment_map(elem_dict):
    range=CRANGE[elem_dict["COORD_RANGE1"]]
    dist=CDIST[elem_dict["COORD_DIST1"]]
    mod_dict={"Coord1ScalingThresholds": SCALINGCOORD[dist][range]}

    range=CRANGE[elem_dict["COORD_RANGE2"]]
    dist=CDIST[elem_dict["COORD_DIST2"]]
    mod_dict["Coord2ScalingThresholds"] = SCALINGCOORD[dist][range]
    
    mod_dict["TelemSrcSel"] = elem_dict["TelemSrcSel"]
    mod_dict["DownstreamWeight"] = elem_dict["DownstreamEXCH"]*7
    mod_dict["LocalWeight"] = elem_dict["LocalEXCH"]*7
    mod_dict["RemoteWeight"] = elem_dict["RemoteEXCH"]*7

    # for element, val in mod_dict:
    #     print(element, val)
    modify_xml(mod_dict)

if __name__=="__main__":
    exp_header = sys.argv[1]
    exp_vals   = sys.argv[2]

    os.makedirs(OPA_RESET_DIR, exist_ok=True)
    var_names  = exp_header.split(',')
    xint = [int(k) for k in exp_vals.split(',')]
    exp_dict = dict(zip(var_names, xint))
    experiment_map(exp_dict)
    with open(OPA_RESET_SIGNAL, 'w') as rf:
        rf.write('1')
            
    # READ the header and the index of the file.
    # var_names = header of exp_file
    # var_vals = index of exp_file


    ## Experiment map should return a dict with the name of the key and their values for this selection.
