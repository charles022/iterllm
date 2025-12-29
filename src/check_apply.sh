#!/bin/bash

# use: check_apply.sh --taskid <taskid> [--apply_to <path>]

# flags
taskid=""
apply_to_path=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --taskid)   taskid="$2"; shift 2 ;;
    --apply_to_path) apply_to_path="$2"; shift 2 ;;
    *) echo "Error: Unexpected argument '$1'"; exit 1 ;;
  esac
done

# validate 1: ensure taskid is present
if [[ -z "$taskid" ]]; then
    echo "Error: --taskid is required."
    echo "Usage: ./check_apply.sh --taskid <id> [--apply_to <path>]"
    exit 1
fi

# validate 2: if apply_to_path was set, ensure it exists
if [[ -n "$apply_path" ]]; then
    if [[ -d "$apply_path" ]]; then
        cd "$apply_path" || exit 1
    else
        echo "Error: Directory '$apply_path' does not exist."
        exit 1
    fi
fi

# get status
taskstatus=$(codex cloud status "$taskid")

# if ready apply, else return status
if [[ "${taskstatus:0:7}" == "[READY]" ]]; then
    echo "Task complete, applying changes"
    codex cloud apply "$taskid"
    echo "Finished applying changes."
else
    echo "Task not ready. Current status:"
    echo "$taskstatus"
fi

