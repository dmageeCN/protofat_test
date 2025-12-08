#!/usr/bin/env python3
"""
PMA Counter Data Parser and Graphing Utilities

This module provides functions to parse PMA counter CSV data, organize it
into a multi-dimensional dictionary structure, and generate visualizations and graphs for analysis.
"""

import csv
import gc
import os
import sys
import logging
import hashlib
from typing import Dict, List, Tuple, Optional, Any, Union
from dataclasses import dataclass
import matplotlib.pyplot as plt
from matplotlib.axes import Axes

# Configure logging
logging.basicConfig(level=logging.WARNING, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Configuration constants
MIN_FIGURE_HEIGHT = 8
MIN_FIGURE_WIDTH = 10
INCHES_PER_ROW = 4
INCHES_PER_COL = 8
DEFAULT_DPI = 100
SUPERTITLE_Y_POSITION = 0.98
TIGHT_LAYOUT_TOP = 0.96

# Performance constants
DEFAULT_MARKERSIZE = 3
DEFAULT_LINEWIDTH = 1
CSV_START_ROW = 2  # Start enumeration at 2 to match file line numbers (header=line 1, first data row=line 2)
AVG_CHARS_PER_CELL = 20  # For CSV size estimation

@dataclass
class PlotConfig:
    """Configuration for plot generation."""
    output_dir: str = "pmaCounterGraphs"
    comparison_vl: str = "Overall"
    min_fig_height: int = 6  # Smaller for individual plots
    min_fig_width: int = 8   # Smaller for individual plots
    row_height: int = INCHES_PER_ROW
    col_width: int = INCHES_PER_COL
    dpi: int = DEFAULT_DPI
    
    # Performance optimization settings
    use_fast_rendering: bool = True
    cache_time_series: bool = True
    optimize_memory: bool = True
    cache_clear_interval: int = 5  # Clear cache every N GUIDs
    individual_subplots: bool = True  # Generate each subplot as separate PNG

# Global configuration instance
config = PlotConfig()

def parse_pma_csv(csv_file_path: str) -> Tuple[Dict[str, Any], List[str]]:
    """
    Parse PMA counter CSV file into a multi-dimensional dictionary structure.
    
    Args:
        csv_file_path (str): Path to the CSV file to parse
        
    Returns:
        Tuple[Dict[str, Any], List[str]]: A tuple containing:
            - Dict[str, Any]: Multi-dimensional dictionary with structure:
                data[GUID][iteration][port][VL][attribute] = value
                Special keys:
                - data[GUID]["Description"] = description string
            - List[str]: List of attribute column names found in the CSV file
    
    Example:
        data, attribute_columns = parse_pma_csv("pmaOut.csv")
        # Access specific value
        xmit_pkts = data["0xd0066a0106000015"]["0"]["57"]["Overall"]["Xmit Pkts"]
        # Get description
        desc = data["0xd0066a0106000015"]["Description"]
        
    Raises:
        FileNotFoundError: If the CSV file doesn't exist
        ValueError: If required headers are missing
    """
    
    if not os.path.exists(csv_file_path):
        raise FileNotFoundError(f"CSV file not found: {csv_file_path}")
    
    # Initialize the main data structure
    data = {}
    
    # Required headers that must be present
    required_headers = {"GUID", "Description", "Port", "Iteration", "VL"}
    
    with open(csv_file_path, 'r', newline='', encoding='utf-8') as csvfile:
        # Read the header line
        csv_reader = csv.reader(csvfile)
        try:
            headers = next(csv_reader)
        except StopIteration:
            raise ValueError("CSV file is empty or has no header")
        headers = [h.strip() for h in headers]
        
        # Validate required headers are present
        header_set = set(headers)
        missing_headers = required_headers - header_set
        if missing_headers:
            raise ValueError(f"Missing required headers: {missing_headers}")
        
        # Get indices for required columns
        guid_idx = headers.index("GUID")
        desc_idx = headers.index("Description")
        port_idx = headers.index("Port")
        iteration_idx = headers.index("Iteration")
        vl_idx = headers.index("VL")
        
        # Get the remaining attribute columns (excluding the required ones)
        attribute_columns = []
        attribute_indices = []
        for i, header in enumerate(headers):
            if header not in required_headers:
                attribute_columns.append(header)
                attribute_indices.append(i)
        
        # Process each data row
        for row_num, row in enumerate(csv_reader, start=CSV_START_ROW):  # row_num matches file line numbers
            if len(row) != len(headers):
                logger.warning(f"Row {row_num} has {len(row)} columns, expected {len(headers)}. Skipping.")
                continue
                
            try:
                # Extract key values
                guid = row[guid_idx].strip()
                description = row[desc_idx].strip()
                port = row[port_idx].strip()
                iteration = row[iteration_idx].strip()
                vl = row[vl_idx].strip()
                
                # Initialize nested structure if needed
                if guid not in data:
                    data[guid] = {"Description": description}
                else:
                    # Validate description consistency for the same GUID
                    existing_description = data[guid]["Description"]
                    if existing_description != description:
                        logger.warning(f"Inconsistent description for GUID {guid}: "
                                     f"existing='{existing_description}', new='{description}'. "
                                     f"Keeping existing description.")
                
                # Initialize iteration level
                if iteration not in data[guid]:
                    data[guid][iteration] = {}
                
                # Initialize port level
                if port not in data[guid][iteration]:
                    data[guid][iteration][port] = {}
                
                # Initialize VL level
                if vl not in data[guid][iteration][port]:
                    data[guid][iteration][port][vl] = {}
                
                # Store attribute values
                for attr_name, attr_idx in zip(attribute_columns, attribute_indices):
                    value_str = row[attr_idx].strip()
                    
                    # Try to convert to appropriate data type
                    try:
                        # Try integer first
                        value = int(value_str)
                    except ValueError:
                        try:
                            # Try float
                            value = float(value_str)
                        except ValueError:
                            # Keep as string
                            value = value_str
                    
                    data[guid][iteration][port][vl][attr_name] = value
                    
            except (IndexError, ValueError) as e:
                logger.warning(f"Error processing row {row_num}: {e}. Skipping.")
                continue
    
    # Return both data and available attribute columns
    return data, attribute_columns


def get_available_attributes(data: Dict[str, Any]) -> List[str]:
    """
    Get available attributes from the parsed data structure.
    
    Args:
        data (Dict[str, Any]): The parsed data structure
        
    Returns:
        List[str]: Available attribute names
        
    Raises:
        ValueError: If the data dictionary is empty or contains no valid data
    """
    # Validate that data is not empty
    if not data:
        raise ValueError("Data dictionary is empty - no attributes can be extracted")
    
    # Get attributes from the first available data point
    for guid in data.keys():
        iterations = [k for k in data[guid].keys() if k != "Description"]
        if iterations:
            ports = list(data[guid][iterations[0]].keys())
            if ports:
                vls = list(data[guid][iterations[0]][ports[0]].keys())
                if vls:
                    return list(data[guid][iterations[0]][ports[0]][vls[0]].keys())
    
    # If we get here, data structure exists but contains no valid measurement data
    raise ValueError("Data dictionary contains no valid measurement data - no attributes found")


class TimeSeriesCache:
    """Encapsulated cache for time series data to improve performance and organization."""
    def __init__(self):
        self._cache = {}
    
    def get(self, guid: str, port: str, vl: str, attr_name: str, iterations_hash: str) -> Optional[List[Union[int, float]]]:
        """Get cached time series data."""
        # Use tuple as cache key to prevent collisions
        cache_key = (guid, port, vl, attr_name, iterations_hash)
        return self._cache.get(cache_key)
    
    def put(self, guid: str, port: str, vl: str, attr_name: str, iterations_hash: str, values: List[Union[int, float]]) -> None:
        """Store time series data in cache."""
        # Use tuple as cache key to prevent collisions
        cache_key = (guid, port, vl, attr_name, iterations_hash)
        self._cache[cache_key] = values
    
    def clear(self) -> None:
        """Clear all cached data."""
        self._cache.clear()
    
    def size(self) -> int:
        """Get current cache size."""
        return len(self._cache)

# Global cache instance
_time_series_cache = TimeSeriesCache()

class DirectoryCache:
    """Cache for created directories to avoid redundant os.makedirs() calls."""
    def __init__(self):
        self._created_dirs = set()
    
    def ensure_directory(self, dir_path: str) -> None:
        """Create directory if it hasn't been created yet."""
        if dir_path not in self._created_dirs:
            os.makedirs(dir_path, exist_ok=True)
            self._created_dirs.add(dir_path)
    
    def clear(self) -> None:
        """Clear the cache of created directories."""
        self._created_dirs.clear()
    
    def size(self) -> int:
        """Get number of cached directories."""
        return len(self._created_dirs)

# Global directory cache instance
_directory_cache = DirectoryCache()

def _extract_time_series(data: Dict[str, Any], guid: str, port: str, vl: str, attr_name: str, iterations: List[str]) -> List[Union[int, float]]:
    """Extract time series data for a specific port, VL, and attribute with caching."""
    if config.cache_time_series:
        # Create a deterministic hash preserving iteration order (order matters for results)
        iterations_str = ','.join(iterations)
        iterations_hash = hashlib.sha256(iterations_str.encode('utf-8')).hexdigest()
        
        cached_values = _time_series_cache.get(guid, port, vl, attr_name, iterations_hash)
        if cached_values is not None:
            return cached_values
    
    values = []
    for iteration in iterations:
        value = get_value(data, guid, iteration, port, vl, attr_name)
        values.append(value if value is not None else 0)
    
    if config.cache_time_series:
        _time_series_cache.put(guid, port, vl, attr_name, iterations_hash, values)
    
    return values


def _plot_vl_data(ax: Axes, data: Dict[str, Any], guid: str, port: str, attr_name: str, iterations: List[str], sample_vls: List[str]) -> None:
    """Plot VL data for a specific port and attribute with optimizations."""
    for vl in sample_vls:
        values = _extract_time_series(data, guid, port, vl, attr_name, iterations)
        label = vl if vl == "Overall" else f'VL {vl}'
        ax.plot(iterations, values, label=label, marker='o', markersize=DEFAULT_MARKERSIZE, linewidth=DEFAULT_LINEWIDTH)


def _setup_subplot(ax: Axes, title: str, ylabel: str) -> None:
    """Setup common subplot properties."""
    ax.set_title(title)
    ax.legend()
    ax.set_xlabel('Iteration')
    ax.set_ylabel(ylabel)
    ax.grid(True)


def _plot_port_comparison(ax: Axes, data: Dict[str, Any], guid: str, ports: List[str], attr_name: str, vl: str, iterations: List[str]) -> None:
    """Plot port comparison data for overall graphs with optimizations."""
    for port in ports:
        values = _extract_time_series(data, guid, port, vl, attr_name, iterations)
        ax.plot(iterations, values, label=f'Port {port}', marker='o', markersize=DEFAULT_MARKERSIZE, linewidth=DEFAULT_LINEWIDTH)


def _format_vl_title(vl: str) -> str:
    """Format VL for display in titles."""
    return vl if vl == "Overall" else f"VL {vl}"


def _create_individual_subplot(data: Dict[str, Any], guid: str, port: str, attr_name: str, iterations: List[str], sample_vls: List[str], output_prefix: str) -> None:
    """Create individual subplot as its own figure."""
    plt.figure(figsize=(config.min_fig_width, config.min_fig_height))
    ax = plt.gca()
    
    _plot_vl_data(ax, data, guid, port, attr_name, iterations, sample_vls)
    
    description = get_description(data, guid) or "Unknown"
    title = f'GUID {guid} Port {port} {attr_name}\n{description}'
    _setup_subplot(ax, title, attr_name)
    
    # Create directory structure: pmaCounterGraphs/guid_<GUID>/<graph_type>/port_<PORT>
    guid_dir = os.path.join(config.output_dir, f'guid_{guid}')
    type_dir = os.path.join(guid_dir, output_prefix)
    port_dir = os.path.join(type_dir, f'port_{port}')
    _directory_cache.ensure_directory(port_dir)
    
    # Save with descriptive filename in port subdirectory
    filename = f'{output_prefix}_{attr_name.replace(" ", "_")}.png'
    output_path = os.path.join(port_dir, filename)
    plt.tight_layout()
    plt.savefig(output_path, dpi=config.dpi, bbox_inches='tight')
    plt.close()
    

def _create_individual_comparison_subplot(data: Dict[str, Any], guid: str, ports: List[str], attr_name: str, vl: str, iterations: List[str], output_prefix: str) -> None:
    """Create individual port comparison subplot as its own figure."""
    plt.figure(figsize=(config.min_fig_width, config.min_fig_height))
    ax = plt.gca()
    
    _plot_port_comparison(ax, data, guid, ports, attr_name, vl, iterations)
    
    description = get_description(data, guid) or "Unknown"
    title_vl = _format_vl_title(vl)
    title = f'GUID {guid} {title_vl} {attr_name} (All Ports)\n{description}'
    _setup_subplot(ax, title, attr_name)
    
    # Create directory structure: pmaCounterGraphs/guid_<GUID>/<graph_type> (overall graphs in type dir)
    guid_dir = os.path.join(config.output_dir, f'guid_{guid}')
    type_dir = os.path.join(guid_dir, output_prefix)
    _directory_cache.ensure_directory(type_dir)
    
    # Save with descriptive filename in type subdirectory
    vl_safe = vl.replace(" ", "_")
    filename = f'{output_prefix}_{vl_safe}_{attr_name.replace(" ", "_")}_all_ports.png'
    output_path = os.path.join(type_dir, filename)
    plt.tight_layout()
    plt.savefig(output_path, dpi=config.dpi, bbox_inches='tight')
    plt.close()




def _get_common_data_structure(data: Dict[str, Any], guid: str) -> Tuple[List[str], List[str], List[str]]:
    """Extract common data structure elements."""
    iterations = sorted(data[guid].keys())
    iterations = [it for it in iterations if it != "Description"]
    ports = sorted(data[guid][iterations[0]].keys())
    sample_vls = list(data[guid][iterations[0]][ports[0]].keys())
    return iterations, ports, sample_vls


def get_value(data: Dict[str, Any], guid: str, iteration: str, port: str, vl: str, attribute: str) -> Optional[Union[int, float, str]]:
    """
    Safely retrieve a value from the parsed data structure.
    
    Args:
        data: The parsed data structure
        guid: GUID identifier
        iteration: Iteration number
        port: Port number
        vl: VL identifier
        attribute: Attribute name
        
    Returns:
        The value if found, None otherwise
    """
    try:
        return data[guid][iteration][port][vl][attribute]
    except KeyError as e:
        logger.debug(f"Key not found: {e}")
        return None

def get_description(data: Dict[str, Any], guid: str) -> Optional[str]:
    """
    Retrieve the description for a given GUID.
    
    Args:
        data: The parsed data structure
        guid: GUID identifier

    Returns:
        The description if found, None otherwise
    """
    try:
        return data[guid]["Description"]
    except KeyError as e:
        logger.debug(f"Key not found: {e}")
        return None
    

def create_xmit_rcv_pkt_graphs(data: Dict[str, Any], guid: str, available_attributes: List[str]) -> None:
    """
    Create individual graphs of transmitted and received packets over iterations for a specific GUID and port.
    Each port/attribute combination gets its own PNG file for optimal performance.
    Only creates graphs for attributes that exist in the data.

    Args:
        data: The parsed PMA data structure
        guid: The GUID to graph data for
        available_attributes: List of available attribute column names
    """
    description = get_description(data, guid)
    if description is None:
        logger.info(f"No description found for GUID {guid}. Cannot create packet graphs.")
        return
    
    # Check which packet attributes are available
    packet_attrs = []
    if "Xmit Pkts" in available_attributes:
        packet_attrs.append("Xmit Pkts")
    if "Rcv Pkts" in available_attributes:
        packet_attrs.append("Rcv Pkts")
    
    # If no packet attributes available, don't create graphs
    if not packet_attrs:
        logger.info(f"No packet attributes (Xmit Pkts, Rcv Pkts) found for GUID {guid}. Skipping packet graphs.")
        return
        
    iterations, ports, sample_vls = _get_common_data_structure(data, guid)
    
    # Create individual subplot for each port/attribute combination
    for port in ports:
        for attr_name in packet_attrs:
            _create_individual_subplot(data, guid, port, attr_name, iterations, sample_vls, "packets")
    
    # Create comparison graphs showing all ports for each packet attribute
    for attr_name in packet_attrs:
        _create_individual_comparison_subplot(data, guid, ports, attr_name, config.comparison_vl, iterations, "packets")

def create_congestion_graphs(data: Dict[str, Any], guid: str, available_attributes: List[str]) -> None:
    """
    Create individual graphs of congestion metrics over iterations for a specific GUID and port.
    Each port/attribute combination gets its own PNG file for optimal performance.
    Only creates graphs for attributes that exist in the data.

    Args:
        data: The parsed PMA data structure
        guid: The GUID to graph data for
        available_attributes: List of available attribute column names
    """
    description = get_description(data, guid)
    if description is None:
        logger.info(f"No description found for GUID {guid}. Cannot create congestion graphs.")
        return
    
    # Check which congestion attributes are available
    congestion_attrs = []
    if "Xmit Time Cong" in available_attributes:
        congestion_attrs.append("Xmit Time Cong")
    if "Xmit Wait" in available_attributes:
        congestion_attrs.append("Xmit Wait")
    if "Congestion Discards" in available_attributes:
        congestion_attrs.append("Congestion Discards")
    
    # If no congestion attributes available, don't create graphs
    if not congestion_attrs:
        logger.info(f"No congestion attributes (Xmit Time Cong, Xmit Wait, Congestion Discards) found for GUID {guid}. Skipping congestion graphs.")
        return
        
    iterations, ports, sample_vls = _get_common_data_structure(data, guid)
    
    # Create individual subplot for each port/attribute combination
    for port in ports:
        for attr_name in congestion_attrs:
            _create_individual_subplot(data, guid, port, attr_name, iterations, sample_vls, "congestion")
    
    # Create comparison graphs showing all ports for each congestion attribute
    for attr_name in congestion_attrs:
        _create_individual_comparison_subplot(data, guid, ports, attr_name, config.comparison_vl, iterations, "congestion")

def create_bubble_graphs(data: Dict[str, Any], guid: str, available_attributes: List[str]) -> None:
    """
    Create graphs of bubble metrics over iterations for a specific GUID and port.
    Each port gets subplots for different bubble attributes, with all VLs plotted.
    Additional subplots show Overall data across all ports for each attribute.
    Only creates graphs if at least one bubble attribute exists in the data.

    Args:
        data: The parsed PMA data structure
        guid: The GUID to graph data for
        available_attributes: List of available attribute column names
    """
    description = get_description(data, guid)
    if description is None:
        logger.info(f"No description found for GUID {guid}. Cannot create bubble graph.")
        return
    
    # Check which core bubble attributes are available (excluding Error Counter Summary)
    core_bubble_attrs = []
    if "Rcv Bubble" in available_attributes:
        core_bubble_attrs.append("Rcv Bubble")
    if "Xmit Wasted BW" in available_attributes:
        core_bubble_attrs.append("Xmit Wasted BW")
    if "Xmit Wait Data" in available_attributes:
        core_bubble_attrs.append("Xmit Wait Data")
    
    # Check if Error Counter Summary is available
    has_error_counter = "Error Counter Summary" in available_attributes
    
    # If no core bubble attributes and no Error Counter Summary, skip the graph
    if not core_bubble_attrs and not has_error_counter:
        logger.info(f"No bubble attributes (Rcv Bubble, Xmit Wasted BW, Xmit Wait Data, Error Counter Summary) found for GUID {guid}. Skipping bubble graphs.")
        return
        
    iterations, ports, sample_vls = _get_common_data_structure(data, guid)
    
    # Create individual subplot for each port/core bubble attribute combination
    for port in ports:
        for attr_name in core_bubble_attrs:
            _create_individual_subplot(data, guid, port, attr_name, iterations, sample_vls, "bubble")
    
    # Create comparison graphs showing all ports for each bubble attribute
    for attr_name in core_bubble_attrs:
        _create_individual_comparison_subplot(data, guid, ports, attr_name, config.comparison_vl, iterations, "bubble")
    
    # Special handling for Error Counter Summary (always uses Overall VL)
    if has_error_counter:
        _create_individual_comparison_subplot(data, guid, ports, "Error Counter Summary", "Overall", iterations, "bubble")




def _clear_performance_cache() -> None:
    """Clear performance caches to free memory."""
    cache_size = _time_series_cache.size()
    dir_cache_size = _directory_cache.size()
    
    _time_series_cache.clear()
    _directory_cache.clear()
    
    gc.collect()
    
    logger.debug(f"Cleared {cache_size} cached time series entries and {dir_cache_size} directory entries")

def create_graphs(data: Dict[str, Any], available_attributes: List[str]) -> None:
    """Create individual graphs from the parsed PMA data with performance optimizations.
    
    Args:
        data: The parsed PMA data structure
        available_attributes: List of available attribute column names
        
    Raises:
        ValueError: If configuration is invalid
        OSError: If output directory cannot be created
    """
    # Initialize directory cache for this graph generation session
    _directory_cache.clear()
    
    # Validate configuration before proceeding
    _validate_config()
    
    # Configure matplotlib for better performance with individual plots
    if config.use_fast_rendering:
        plt.rcParams['figure.max_open_warning'] = 0
        plt.rcParams['font.size'] = 9  # Slightly larger for individual plots
        plt.rcParams['lines.markersize'] = 4
        plt.rcParams['lines.linewidth'] = 1.5
        # Use non-interactive backend for better performance
        plt.switch_backend('Agg')
    
    guids = list(data.keys())
    
    print(f"Generating individual subplot PNG files for {len(guids)} GUIDs...")
    
    for i, guid in enumerate(guids):
        if config.use_fast_rendering:
            print(f"Processing GUID {i+1}/{len(guids)}: {guid}")
        
        # Each function now creates multiple individual PNG files
        create_xmit_rcv_pkt_graphs(data, guid, available_attributes)
        create_congestion_graphs(data, guid, available_attributes)
        create_bubble_graphs(data, guid, available_attributes)
        
        # Clear cache periodically to manage memory
        if config.cache_time_series and (i + 1) % config.cache_clear_interval == 0:
            _clear_performance_cache()
    
    # Final cleanup
    _clear_performance_cache()
    print(f"Individual subplot generation complete. Files saved to: {config.output_dir}")
    
def _validate_comparison_vl(data: Dict[str, Any], comparison_vl: str) -> bool:
    """Validate that the comparison VL exists in the dataset.
    
    Args:
        data: The parsed PMA data structure  
        comparison_vl: The VL to validate
        
    Returns:
        bool: True if the VL exists, False otherwise
    """
    for guid in data.keys():
        iterations = [k for k in data[guid].keys() if k != "Description"]
        if iterations:
            ports = list(data[guid][iterations[0]].keys())
            if ports:
                vls = list(data[guid][iterations[0]][ports[0]].keys())
                if comparison_vl in vls:
                    return True
    return False

def _validate_config() -> None:
    """Validate configuration settings."""
    if config.dpi < 50 or config.dpi > 300:
        logger.warning(
            f"DPI value {config.dpi} is outside the recommended range (50-300). "
            "DPI values below 50 may produce low-quality images, while values above 300 "
            "may result in large file sizes without significant quality improvement."
        )
    
    if config.cache_clear_interval < 1:
        raise ValueError("cache_clear_interval must be at least 1")
    
    if not os.path.exists(config.output_dir):
        logger.info(f"Creating output directory: {config.output_dir}")
        _directory_cache.ensure_directory(config.output_dir)


def print_usage():
    print("Usage: python pmaCounterGraphing.py <path_to_csv> [<COMPARISON_VL>]")
    print("  <path_to_csv>: Path to the PMA counter CSV file to parse")
    print("  [COMPARISON_VL]: (Optional) VL to use for comparison graphs (default: 'Overall')")
    sys.exit(1)

# Example usage and testing
if __name__ == "__main__":
    # Take CSV file path from command line argument
    if len(sys.argv) < 2:
        print_usage()

    csv_path = sys.argv[1]
    try:
        pma_data, available_attributes = parse_pma_csv(csv_path)
        print(f"Successfully parsed {csv_path}")
        print(f"Available attributes: {available_attributes}")
        
        # Set and validate comparison_vl immediately after data parsing
        if len(sys.argv) >= 3:
            # Set comparison_vl from command line
            config.comparison_vl = sys.argv[2]
            print(f"COMPARISON_VL set to: {config.comparison_vl}")
            
            # Validate immediately and fallback if necessary
            if not _validate_comparison_vl(pma_data, config.comparison_vl):
                logger.warning(f"Comparison VL '{config.comparison_vl}' not found in data. Using 'Overall' as fallback.")
                config.comparison_vl = "Overall"
        
        print(f"Using comparison VL: {config.comparison_vl}")
        
        guid_count = len(pma_data)
        print(f"Found {guid_count} GUIDs in dataset")
        
        create_graphs(pma_data, available_attributes)
        print(f"Graph generation completed successfully!")
        
    except FileNotFoundError:
        print(f"Error: File not found: {csv_path}")
        print("Please check the file path and try again.")
        sys.exit(1)
    except ValueError as e:
        print(f"Error: Invalid data format - {str(e)}")
        print("Please ensure the CSV file has the correct format.")
        sys.exit(1)
    except OSError as e:
        print(f"Error: File system error - {str(e)}")
        print("Please check file permissions and disk space.")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        logger.exception("Unexpected error during execution")
        sys.exit(1)

