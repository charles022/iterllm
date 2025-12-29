#!/bin/bash

# use: ex.sh --envid "$envid" --task "$task"
# envid: charles022/sample_project

envid="charles022/sample_project" # default

while [[ $# -gt 0 ]]; do
  case $1 in
    --task)  task="$2";  shift 2 ;;
    --envid) envid="$2"; shift 2 ;;
    *) echo "Error: Unexpected argument '$1'"; exit 1 ;;
  esac
done


taskid=$(codex cloud exec --env "$envid" "$task")

echo "$taskid"

# taskstatus=$(codex cloud status "$taskid")
# 
# if [[ "${taskstatus:0:7}" == "[READY]" ]]; then
#   codex cloud apply "$taskid"


