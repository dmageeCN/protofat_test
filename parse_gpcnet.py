#!/usr/bin/env python3
"""
GPCNET Log Parser - Parses network test logs into JSON/CSV
Usage: python parse_gpcnet.py <logfile> [--format json|csv]
"""

import json
import csv
import sys
import argparse

def parse_gpcnet_log(filepath: str) -> Dict[str, Any]:
    """Parse the entire GPCNET log file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    data = {
        'test_info': {},
    }
    testexec = 'default'
    tablerow=0
    testheader=[]
    for i in range(len(lines)):
        line = lines[i].strip()
        
        # Parse test metadata
        if i==0:
            topData=line.split(' - ')
            data['test_info']['date'] = topData[1]
            data['test_info']['config'] = topData[2]
        
        elif line.startswith("GPCNET"):
            splitline = line.split(' ')
            nodes = int(splitline[-1])
            testexec = splitline[1]
            data['test_info']['nodes'] = nodes
            data[testexec] = {}
    
        elif line.startswith("mpirun"):
            data['test_info']['mpi_line'] = line
        
        # # Parse main tables
        # if line.startswith('+----'):
        #     continue
        elif line.count('|') == 2:
            titleline=line.strip('|').strip(' ')
            data[testexec][titleline] = {}
        
        elif 'Avg(Worst)' in line:
            testheader = [k.strip(' ') for k in line.split('|') if k][1:]

        elif line.startswith('|'):
            testresult=[k.strip(' ') for k in line.split('|') if k]
            print(testresult, testheader)
            data[testexec][titleline][testresult[0]] = dict(zip(testheader, 
                                                                testresult[1:]))

    
    return data


def write_json(data: Dict, output_file: str):
    """Write data to JSON file."""
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Written to {output_file}")


def write_csv(data: Dict, output_prefix: str):
    """Write data to multiple CSV files."""
    
    # Isolated Network Tests
    with open(f"{output_prefix}_isolated_network.csv", 'w', newline='') as f:
        if data['isolated_network_tests']:
            writer = csv.DictWriter(f, fieldnames=data['isolated_network_tests'][0].keys())
            writer.writeheader()
            writer.writerows(data['isolated_network_tests'])
    
    # Network Load Tests - Isolated
    if data['network_load_tests']['isolated_network_tests']:
        with open(f"{output_prefix}_load_isolated.csv", 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data['network_load_tests']['isolated_network_tests'][0].keys())
            writer.writeheader()
            writer.writerows(data['network_load_tests']['isolated_network_tests'])
    
    # Congestion Tests
    if data['network_load_tests']['isolated_congestion_tests']:
        with open(f"{output_prefix}_congestion.csv", 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data['network_load_tests']['isolated_congestion_tests'][0].keys())
            writer.writeheader()
            writer.writerows(data['network_load_tests']['isolated_congestion_tests'])
    
    # Congestion Impact
    if data['network_load_tests']['congestion_impact']:
        with open(f"{output_prefix}_impact.csv", 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data['network_load_tests']['congestion_impact'][0].keys())
            writer.writeheader()
            writer.writerows(data['network_load_tests']['congestion_impact'])
    
    print(f"Written CSV files with prefix: {output_prefix}_*.csv")


def main():
    parser = argparse.ArgumentParser(description='Parse GPCNET log files')
    parser.add_argument('logfile', help='Path to GPCNET log file')
    parser.add_argument('--format', choices=['json', 'csv', 'both'], default='json',
                       help='Output format (default: json)')
    parser.add_argument('--output', default='gpcnet_results',
                       help='Output file name (without extension)')
    
    args = parser.parse_args()
    
    print(f"Parsing {args.logfile}...")
    data = parse_gpcnet_log(args.logfile)
    
    if args.format in ['json', 'both']:
        write_json(data, f"{args.output}.json")
    
    if args.format in ['csv', 'both']:
        write_csv(data, args.output)
    
    print("Done!")


if __name__ == '__main__':
    main()
