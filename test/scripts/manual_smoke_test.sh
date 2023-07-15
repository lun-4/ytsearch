#!/bin/sh

set -eux

HOST=$1
search_param=${SEARCH:-"urban+rescue+ranch"}

hello_results=$(curl -A 'UnityWebRequest' -v "http://$HOST/api/v1/hello")
printf "%s" "$hello_results" > helltest.json
is_online=$(printf "%s" "$hello_results" | jq -r .online)
if [ "$is_online" != "true" ]; then
  echo "its not online"
  exit 1
fi

trending_tab_slot_id=$(printf "%s" "$hello_results" | jq -r '.trending_tab.search_results[] | select(.type == "video") | .slot_id' | head -n 1)


check_slot(){
  slot_id=$1

  quest_request=$(curl -w '%{http_code}' -o /dev/null -A 'stagefright' "http://$HOST/a/1/sl/$slot_id")
  if [ "$quest_request" != "302" ]; then
    echo "expected 302, got $quest_request"
    exit 1
  fi

  unity_request=$(curl -w '%{http_code}' -o /dev/null -A 'UnityWebRequest' "http://$HOST/a/1/sl/$slot_id")
  if [ "$unity_request" != "200" ]; then
    echo "expected 200, got $unity_request"
    exit 1
  fi

  any_request=$(curl -w '%{http_code}' -o /dev/null "http://$HOST/a/1/sl/$slot_id")
  if [ "$any_request" != "302" ]; then
    echo "expected 302, got $any_request"
    exit 1
  fi
}

check_slot "$trending_tab_slot_id"

# check search

result=$(curl -A 'UnityWebRequest' -v -G "http://$HOST/a/1/s" --data-urlencode "q=$search_param")
first_video_slot_id=$(echo "$result" | jq -r '.search_results[] | select(.type == "video") | .slot_id' | head -n 1)
echo "got slot $first_video_slot_id"

check_slot "$first_video_slot_id"
echo "pass!"
