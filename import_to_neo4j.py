#!/usr/bin/env python3

import re
import sys
from neo4j import GraphDatabase
import argparse

class PackageGraphImporter:
    def __init__(self, uri, user, password):
        self.driver = GraphDatabase.driver(uri, auth=(user, password))

    def close(self):
        self.driver.close()

    def clear_database(self, namespace=None):
        """Clear existing data from the database, optionally filtered by namespace."""
        with self.driver.session() as session:
            if namespace:
                # Clear only nodes from specific namespace
                session.run("""
                    MATCH (n) 
                    WHERE n.namespace = $namespace 
                    DETACH DELETE n
                """, namespace=namespace)
                print(f"Cleared existing data for namespace '{namespace}' from database")
            else:
                # Clear all data
                session.run("MATCH (n) DETACH DELETE n")
                print("Cleared all existing data from database")

    def create_constraints(self):
        """Create constraints and indexes for better performance."""
        with self.driver.session() as session:
            # Create composite constraint for Package nodes (name + namespace)
            try:
                session.run("""
                    CREATE CONSTRAINT package_name_namespace IF NOT EXISTS 
                    FOR (p:Package) REQUIRE (p.name, p.namespace) IS UNIQUE
                """)
            except:
                # Constraint might already exist
                pass

            # Create composite constraint for Layer nodes (name + namespace)
            try:
                session.run("""
                    CREATE CONSTRAINT layer_name_namespace IF NOT EXISTS 
                    FOR (l:Layer) REQUIRE (l.name, l.namespace) IS UNIQUE
                """)
            except:
                # Constraint might already exist
                pass

            # Create indexes for better query performance
            try:
                session.run("CREATE INDEX package_namespace IF NOT EXISTS FOR (p:Package) ON (p.namespace)")
                session.run("CREATE INDEX layer_namespace IF NOT EXISTS FOR (l:Layer) ON (l.namespace)")
            except:
                pass

            print("Created constraints and indexes")

    def parse_combined_output(self, filepath):
        """Parse the combined_output.txt file and return structured data."""
        packages = {}
        current_package = None
        in_dependencies = False

        with open(filepath, 'r') as f:
            for line in f:
                line = line.rstrip()

                # Skip header lines
                if line.startswith("Package Dependency and Layer Information") or line.startswith("="):
                    continue

                # Check for package name
                if line.startswith("Package: "):
                    current_package = line.replace("Package: ", "").strip()
                    packages[current_package] = {
                        'layers': [],
                        'dependencies': []
                    }
                    in_dependencies = False

                # Check for layers
                elif line.strip().startswith("Layers: ") and current_package:
                    layers_str = line.strip().replace("Layers: ", "")
                    if layers_str != "(not found in package-layers.txt)":
                        layers = [l.strip() for l in layers_str.split(',')]
                        packages[current_package]['layers'] = layers

                # Check for dependencies section
                elif line.strip() == "Dependencies:" and current_package:
                    in_dependencies = True

                # Parse dependency lines
                elif in_dependencies and line.strip().startswith("- "):
                    # Extract dependency name (before the parentheses)
                    dep_match = re.match(r'\s*-\s*([^\s(]+)', line)
                    if dep_match:
                        dep_name = dep_match.group(1)
                        packages[current_package]['dependencies'].append(dep_name)

                # End of dependencies
                elif line.strip() == "Dependencies: none" and current_package:
                    in_dependencies = False

        return packages

    def import_data(self, packages_data, namespace):
        """Import the parsed data into Neo4j with namespace support."""
        with self.driver.session() as session:
            # First, create all Layer nodes
            all_layers = set()
            for package_data in packages_data.values():
                all_layers.update(package_data['layers'])

            for layer in all_layers:
                session.run("""
                    MERGE (l:Layer {name: $name, namespace: $namespace})
                """, name=layer, namespace=namespace)

            print(f"Created {len(all_layers)} layer nodes for namespace '{namespace}'")

            # Create Package nodes and relationships
            package_count = 0
            dependency_count = 0
            belongs_to_count = 0

            for package_name, package_data in packages_data.items():
                # Create package node with namespace
                session.run("""
                    MERGE (p:Package {name: $name, namespace: $namespace})
                """, name=package_name, namespace=namespace)
                package_count += 1

                # Create BELONGS_TO relationships with layers
                for layer in package_data['layers']:
                    session.run("""
                        MATCH (p:Package {name: $package_name, namespace: $namespace})
                        MATCH (l:Layer {name: $layer_name, namespace: $namespace})
                        MERGE (p)-[:BELONGS_TO {namespace: $namespace}]->(l)
                    """, package_name=package_name, layer_name=layer, namespace=namespace)
                    belongs_to_count += 1

                # Progress indicator
                if package_count % 100 == 0:
                    print(f"Processed {package_count} packages...")

            print(f"Created {package_count} package nodes for namespace '{namespace}'")
            print(f"Created {belongs_to_count} BELONGS_TO relationships")

            # Create DEPENDS_ON relationships (only within the same namespace)
            for package_name, package_data in packages_data.items():
                for dependency in package_data['dependencies']:
                    session.run("""
                        MATCH (p1:Package {name: $package_name, namespace: $namespace})
                        MATCH (p2:Package {name: $dependency_name, namespace: $namespace})
                        MERGE (p1)-[:DEPENDS_ON {namespace: $namespace}]->(p2)
                    """, package_name=package_name, dependency_name=dependency, namespace=namespace)
                    dependency_count += 1

                # Progress indicator
                if dependency_count > 0 and dependency_count % 100 == 0:
                    print(f"Created {dependency_count} dependency relationships...")

            print(f"Created {dependency_count} DEPENDS_ON relationships for namespace '{namespace}'")

    def verify_import(self, namespace=None):
        """Run some verification queries to check the import."""
        with self.driver.session() as session:
            # Build WHERE clause for namespace filtering
            where_clause = "WHERE p.namespace = $namespace" if namespace else ""
            namespace_param = {"namespace": namespace} if namespace else {}
            
            # Count nodes
            package_count = session.run(f"""
                MATCH (p:Package) 
                {where_clause}
                RETURN count(p) as count
            """, **namespace_param).single()['count']
            
            layer_count = session.run(f"""
                MATCH (l:Layer) 
                {'WHERE l.namespace = $namespace' if namespace else ''}
                RETURN count(l) as count
            """, **namespace_param).single()['count']

            # Count relationships
            depends_count = session.run(f"""
                MATCH ()-[r:DEPENDS_ON]->() 
                {'WHERE r.namespace = $namespace' if namespace else ''}
                RETURN count(r) as count
            """, **namespace_param).single()['count']
            
            belongs_count = session.run(f"""
                MATCH ()-[r:BELONGS_TO]->() 
                {'WHERE r.namespace = $namespace' if namespace else ''}
                RETURN count(r) as count
            """, **namespace_param).single()['count']

            # Find packages with most dependencies
            top_deps = session.run(f"""
                MATCH (p:Package)-[:DEPENDS_ON]->(dep)
                {where_clause}
                RETURN p.name as package, count(dep) as dep_count
                ORDER BY dep_count DESC
                LIMIT 5
            """, **namespace_param).data()

            print(f"\n=== Import Verification {'for namespace ' + namespace if namespace else ''} ===")
            print(f"Total Package nodes: {package_count}")
            print(f"Total Layer nodes: {layer_count}")
            print(f"Total DEPENDS_ON relationships: {depends_count}")
            print(f"Total BELONGS_TO relationships: {belongs_count}")
            print("\nTop 5 packages by dependency count:")
            for item in top_deps:
                print(f"  {item['package']}: {item['dep_count']} dependencies")

    def list_namespaces(self):
        """List all existing namespaces in the database."""
        with self.driver.session() as session:
            namespaces = session.run("""
                MATCH (n) 
                WHERE n.namespace IS NOT NULL
                RETURN DISTINCT n.namespace as namespace
                ORDER BY namespace
            """).data()
            
            print("\n=== Existing Namespaces ===")
            if namespaces:
                for ns in namespaces:
                    print(f"  - {ns['namespace']}")
            else:
                print("  No namespaces found")

def main():
    parser = argparse.ArgumentParser(description='Import package dependency data into Neo4j with namespace support')
    parser.add_argument('input_file', help='Path to combined_output.txt')
    parser.add_argument('--namespace', required=True, help='Namespace for this import (e.g., oss, vendor, internal)')
    parser.add_argument('--uri', default='bolt://localhost:7687', help='Neo4j connection URI (default: bolt://localhost:7687)')
    parser.add_argument('--user', default='neo4j', help='Neo4j username (default: neo4j)')
    parser.add_argument('--password', required=True, help='Neo4j password')
    parser.add_argument('--clear', action='store_true', help='Clear existing data for this namespace before import')
    parser.add_argument('--clear-all', action='store_true', help='Clear ALL existing data before import (use with caution!)')
    parser.add_argument('--list-namespaces', action='store_true', help='List existing namespaces and exit')

    args = parser.parse_args()

    # Create importer
    importer = PackageGraphImporter(args.uri, args.user, args.password)

    try:
        # List namespaces and exit if requested
        if args.list_namespaces:
            importer.list_namespaces()
            return

        # Clear database if requested
        if args.clear_all:
            importer.clear_database()
        elif args.clear:
            importer.clear_database(args.namespace)

        # Create constraints
        importer.create_constraints()

        # Parse the input file
        print(f"Parsing {args.input_file}...")
        packages_data = importer.parse_combined_output(args.input_file)
        print(f"Found {len(packages_data)} packages to import into namespace '{args.namespace}'")

        # Import the data
        print(f"Importing data to Neo4j with namespace '{args.namespace}'...")
        importer.import_data(packages_data, args.namespace)

        # Verify the import
        importer.verify_import(args.namespace)

        print(f"\nImport completed successfully for namespace '{args.namespace}'!")

    finally:
        importer.close()

if __name__ == "__main__":
    main()
