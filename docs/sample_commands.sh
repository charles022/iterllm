#!/bin/bash

# use: ex.sh -e "$envid" -t "$task"
# envid: charles022/sample_project

while getopts "t:e:" opt; do
  case $opt in
    t) task="$OPTARG" ;;
    e) envid="$OPTARG" ;;
  esac
done

taskit=$(codex cloud exec --env "$envid" "$task")




taskid=$(codex cloud exec --env myenv "<task>")

taskstatus=$(codex cloud status "$taskid")

if [[ "${taskstatus:0:7}" == "[READY]" ]]; then
  codex cloud apply "$taskid"






codex cloud exec ...





1) taskid=$(codex cloud exec --env myenv "<task>")

returns taskID which IS the url for monitoring the task via the web ui
ie...
https://chatgpt.com/codex/tasks/task_e_6950526d82588330acae5990f198c79e
2) taskstatus=$(codex cloud status "$taskid")

when it shows complete, proceed
3) codex cloud apply "$taskid"

applies the changes to the project on the local machine
optional 4) git add -A; git commit -m "..."; git push

merge changes
codex cli does not have the ability to merge changes or create pull requests
pull requests CAN (but dont do this) be added through web ui then merged with git, but this is not recommended for our workflow because it defeats the purpose of cli and headless actions


# check every 30 seconds, when ready, apply changes

while true; do

  taskstatus=$(codex cloud status "$taskid")

  if [[ "${taskstatus:0:7}" == "[READY]" ]]; then

    echo "ready"

    codex cloud apply "$taskid"

    echo "ran codex cloud apply <taskid>"

    break # <--- This exits the "while true" loop

  else

    echo "not ready, sleeping for 30 seconds"

    sleep 30 

  fi

done  

echo "done with task"



