#!/bin/bash
set -e

# Display help message if requested
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  echo "Usage: $0 [keyword]"
  echo ""
  echo "Terminates processes containing the specified keyword."
  echo "If no keyword is provided, uses the current directory name."
  echo ""
  echo "Options:"
  echo "  -h, --help    Show this help message and exit"
  exit 0
fi

# Use provided keyword if available, otherwise use current directory basename
if [ $# -gt 0 ]; then
  keyword="$1"
  echo "Using provided keyword: '${keyword}'"
else
  # Get the basename of the current working directory as the default keyword
  keyword=$(basename "${PWD}")
  echo "Using current directory name as keyword: '${keyword}'"
fi

echo "Cleaning up processes containing keyword '${keyword}'..."

# Find processes containing the keyword, excluding grep and current script
processes=$(ps aux | grep -i "${keyword}" | grep -v "grep" | grep -v "cleanup_orphan_process.sh")

# Check if any processes were found
if [ -z "$processes" ]; then
  echo "No processes found containing keyword '${keyword}'"
  exit 0
fi

# Display the found processes
echo "Found the following processes:"
echo "$processes"

# Extract PIDs
pids=$(echo "$processes" | awk '{print $2}')
echo "Process IDs to terminate: $pids"

# Terminate processes
for pid in $pids; do
  echo "Terminating process $pid"
  kill -15 "$pid" 2>/dev/null || echo "Warning: Failed to terminate process $pid"
done

# Wait and check
sleep 1
echo "Cleanup completed."