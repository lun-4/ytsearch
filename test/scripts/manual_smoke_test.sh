#!/bin/sh

set -eux

HOST=$1
search_param=${SEARCH:-"urban+rescue+ranch"}

hello_results=$(curl -A 'UnityWebRequest' -v "http://$HOST/api/v5/hello/smoke_test")
printf "%s" "$hello_results"
is_online=$(printf "%s" "$hello_results" | jq -r .online)
if [ "$is_online" != "true" ]; then
  echo "its not online"
  exit 1
fi

trending_tab_slot_id=$(printf "%s" "$hello_results" | jq -r '.trending_tab.search_results[] | select(.type == "video") | .slot_id' | head -n 1)


check_slot(){
  slot_id=$1

  quest_request=$(curl -w '%{http_code}' -o /dev/null -A 'stagefright' "http://$HOST/a/5/sl/$slot_id")
  if [ "$quest_request" != "302" ]; then
    echo "expected 302, got $quest_request"
    exit 1
  fi

  redirect_request=$(curl -w '%{http_code}' -o /dev/null -A 'stagefright' "http://$HOST/a/5/sr/$slot_id")
  if [ "$redirect_request" != "302" ]; then
    echo "expected 302, got $redirect_request"
    exit 1
  fi

  unity_request=$(curl -w '%{http_code}' -o /dev/null -A 'UnityWebRequest' "http://$HOST/a/5/sr/$slot_id")
  if [ "$unity_request" != "200" ]; then
    echo "expected 200, got $unity_request"
    exit 1
  fi

  any_request=$(curl -w '%{http_code}' -o /dev/null "http://$HOST/a/5/sl/$slot_id")
  if [ "$any_request" != "302" ]; then
    echo "expected 302, got $any_request"
    exit 1
  fi
}

check_slot "$trending_tab_slot_id"

# check search

sleep 4
result=$(curl -A 'UnityWebRequest' -v -G "http://$HOST/a/5/s" --data-urlencode "q=$search_param")
first_video_slot_id=$(echo "$result" | jq -r '.search_results[] | select(.type == "video") | .slot_id' | head -n 1)
echo "got slot $first_video_slot_id"

check_slot "$first_video_slot_id"
echo "pass!"
