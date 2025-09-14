import plotly.graph_objects as go
import plotly.io as pio

# Define the nodes with better stage grouping
labels = [
    # Input (0)
    "Input Files",
    
    # Parallel Subdomain Enumeration Stage (1)
    "Subdomain Enum",
    
    # External Sources Stage (2) 
    "External Src",
    
    # Individual subdomain tools (3-11)
    "subfinder", "assetfinder", "amass", "bbot", "subdog", 
    "sudomy", "dnscan", "subdominator", "webcopilot",
    
    # Individual external sources (12-15)
    "crt.sh", "GitHub", "Shrewdeye", "SecurityTrails",
    
    # ASN & CIDR Discovery with components (16-18)
    "ASN Enum", "CIDR WHOIS", "Reverse DNS",
    
    # Data Processing components (19-21)
    "Combine", "Deduplicate", "Unique List",
    
    # Live Host Detection components (22-23)
    "httpx", "nmap",
    
    # Endpoint Discovery components (24-27)
    "wfuzz", "dirb", "gobuster", "dirsearch",
    
    # Final Output (28)
    "Final Output"
]

# Define connections with better flow structure
source = []
target = []
values = []

# Input to main stages (0 -> 1, 2)
source.extend([0, 0])
target.extend([1, 2])
values.extend([5, 3])

# Subdomain Enum stage to individual tools (1 -> 3-11)
for i in range(3, 12):
    source.append(1)
    target.append(i)
    values.append(1)

# External Sources stage to individual sources (2 -> 12-15)
for i in range(12, 16):
    source.append(2)
    target.append(i)
    values.append(1)

# All tools to ASN components (3-15 -> 16-18)
for tool_idx in range(3, 16):
    for asn_idx in range(16, 19):
        source.append(tool_idx)
        target.append(asn_idx)
        values.append(1)

# ASN components to Data Processing components (16-18 -> 19-21)
for asn_idx in range(16, 19):
    for proc_idx in range(19, 22):
        source.append(asn_idx)
        target.append(proc_idx)
        values.append(1)

# Data Processing to Live Host Detection (19-21 -> 22-23)
for proc_idx in range(19, 22):
    for live_idx in range(22, 24):
        source.append(proc_idx)
        target.append(live_idx)
        values.append(2)

# Live Host Detection to Endpoint Discovery (22-23 -> 24-27)
for live_idx in range(22, 24):
    for endpoint_idx in range(24, 28):
        source.append(live_idx)
        target.append(endpoint_idx)
        values.append(1)

# Endpoint Discovery to Final Output (24-27 -> 28)
for endpoint_idx in range(24, 28):
    source.append(endpoint_idx)
    target.append(28)
    values.append(2)

# Create colors for different stages
colors = [
    "#1FB8CD",  # Input
    "#DB4545", "#2E8B57",  # Main stages (Subdomain, External)
    # Subdomain tools
    "#5D878F", "#D2BA4C", "#B4413C", "#964325", "#944454", 
    "#13343B", "#1FB8CD", "#DB4545", "#2E8B57",
    # External sources  
    "#5D878F", "#D2BA4C", "#B4413C", "#964325",
    # ASN & CIDR
    "#944454", "#13343B", "#1FB8CD",
    # Data Processing
    "#DB4545", "#2E8B57", "#5D878F", 
    # Live Detection
    "#D2BA4C", "#B4413C",
    # Endpoint Discovery
    "#964325", "#944454", "#13343B", "#1FB8CD",
    # Final Output
    "#DB4545"
]

# Create the Sankey diagram
fig = go.Figure(data=[go.Sankey(
    node = dict(
        pad = 20,
        thickness = 25,
        line = dict(color = "black", width = 0.5),
        label = labels,
        color = colors
    ),
    link = dict(
        source = source,
        target = target,
        value = values,
        color = "rgba(31, 184, 205, 0.2)"
    ))])

fig.update_layout(
    title="FastRecon Workflow",
    font_size=10
)

# Save as both PNG and SVG
fig.write_image("chart.png")
fig.write_image("chart.svg", format="svg")

fig.show()