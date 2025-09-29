#!/usr/bin/env python3

import re
import sys
from collections import defaultdict

def parse_dot_file(dot_file):
    """Parse the .dot file and extract package dependencies."""
    dependencies = defaultdict(set)
    
    with open(dot_file, 'r') as f:
        for line in f:
            # Match lines like: "package1" -> "package2"
            match = re.match(r'"([^"]+)"\s*->\s*"([^"]+)"', line.strip())
            if match:
                pkg_from = match.group(1)
                pkg_to = match.group(2)
                
                # Remove lib32- prefix
                pkg_from = pkg_from.replace('lib32-', '')
                pkg_to = pkg_to.replace('lib32-', '')
                
                dependencies[pkg_from].add(pkg_to)
    
    return dependencies

def parse_layers_file(layers_file):
    """Parse the package-layers.txt file and extract package to layer mappings."""
    package_layers = {}
    current_package = None
    
    with open(layers_file, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip empty lines and warning/note lines
            if not line or line.startswith('WARNING:') or line.startswith('NOTE:') or line.startswith('Summary:'):
                continue
            
            # Check if this is a package name (ends with colon)
            if line.endswith(':'):
                current_package = line[:-1]  # Remove the colon
                # Remove lib32- prefix
                current_package = current_package.replace('lib32-', '')
            elif current_package and line:
                # This line contains the layer information
                # Extract the layer name (first part before whitespace)
                parts = line.split()
                if parts:
                    layer = parts[0]
                    if current_package not in package_layers:
                        package_layers[current_package] = []
                    package_layers[current_package].append(layer)
    
    return package_layers

def combine_data(dependencies, package_layers):
    """Combine dependency and layer information."""
    result = {}
    
    # Get all unique packages from both sources
    all_packages = set(dependencies.keys()) | set(package_layers.keys())
    
    # Also add packages that only appear as dependencies
    for deps in dependencies.values():
        all_packages.update(deps)
    
    for package in sorted(all_packages):
        result[package] = {
            'dependencies': sorted(list(dependencies.get(package, []))),
            'layers': package_layers.get(package, [])
        }
    
    return result

def output_combined_data(combined_data, output_file):
    """Write the combined data to a file."""
    with open(output_file, 'w') as f:
        f.write("Package Dependency and Layer Information\n")
        f.write("=" * 80 + "\n\n")
        
        for package, info in sorted(combined_data.items()):
            f.write(f"Package: {package}\n")
            
            # Write layers
            if info['layers']:
                f.write(f"  Layers: {', '.join(info['layers'])}\n")
            else:
                f.write("  Layers: (not found in package-layers.txt)\n")
            
            # Write dependencies
            if info['dependencies']:
                f.write("  Dependencies:\n")
                for dep in info['dependencies']:
                    # Get layer info for dependency if available
                    dep_layers = combined_data.get(dep, {}).get('layers', [])
                    if dep_layers:
                        f.write(f"    - {dep} (layers: {', '.join(dep_layers)})\n")
                    else:
                        f.write(f"    - {dep} (layer: unknown)\n")
            else:
                f.write("  Dependencies: none\n")
            
            f.write("\n")

def main():
    if len(sys.argv) != 4:
        print("Usage: python combine_dependencies.py <task-depends-reduced.dot> <package-layers.txt> <output.txt>")
        sys.exit(1)
    
    dot_file = sys.argv[1]
    layers_file = sys.argv[2]
    output_file = sys.argv[3]
    
    print(f"Parsing {dot_file}...")
    dependencies = parse_dot_file(dot_file)
    
    print(f"Parsing {layers_file}...")
    package_layers = parse_layers_file(layers_file)
    
    print("Combining data...")
    combined_data = combine_data(dependencies, package_layers)
    
    print(f"Writing output to {output_file}...")
    output_combined_data(combined_data, output_file)
    
    print(f"Done! Found {len(combined_data)} packages.")
    print(f"Packages with dependencies: {sum(1 for p in combined_data.values() if p['dependencies'])}")
    print(f"Packages with layer info: {sum(1 for p in combined_data.values() if p['layers'])}")

if __name__ == "__main__":
    main()