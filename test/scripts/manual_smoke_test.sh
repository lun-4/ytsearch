#!/bin/sh

set -eux

HOST=$1
HTTP=${HTTP-"http"}
search_param=${2:-"urban+rescue+ranch"}

hello_results=$(curl -A 'UnityWebRequest' -v "$HTTP://$HOST/api/v6/hello/smoke_test")
printf "%s" "$hello_results"
is_online=$(printf "%s" "$hello_results" | jq -r .online)
if [ "$is_online" != "true" ]; then
  echo "its not online"
  exit 1
fi

trending_tab_slot_id=$(printf "%s" "$hello_results" | jq -r '.trending_tab.search_results[] | select(.type == "video") | .slot_id' | head -n 1)


check_slot(){
  slot_id=$1

  quest_request=$(curl -w '%{http_code}' -o /dev/null -A 'stagefright' "$HTTP://$HOST/a/6/sl/$slot_id")
  if [ "$quest_request" != "302" ]; then
    echo "expected 302, got $quest_request"
    exit 1
  fi

  redirect_request=$(curl -w '%{http_code}' -o /dev/null -A 'stagefright' "$HTTP://$HOST/a/6/sr/$slot_id")
  if [ "$redirect_request" != "302" ]; then
    echo "expected 302, got $redirect_request"
    exit 1
  fi

  unity_request=$(curl -w '%{http_code}' -o /dev/null -A 'UnityWebRequest' "$HTTP://$HOST/a/6/sr/$slot_id")
  if [ "$unity_request" != "200" ]; then
    echo "expected 200, got $unity_request"
    exit 1
  fi

  any_request=$(curl -w '%{http_code}' -o /dev/null "$HTTP://$HOST/a/6/sl/$slot_id")
  if [ "$any_request" != "302" ]; then
    echo "expected 302, got $any_request"
    exit 1
  fi
}

check_slot "$trending_tab_slot_id"

# check search

sleep 4
result=$(curl -A 'UnityWebRequest' -v -G "$HTTP://$HOST/a/6/s" --data-urlencode "q=$search_param")
search_slot_id=$(echo "$result" | jq -r '.slot_id' | head -n 1)
atlas_status_code=$(curl -w '%{http_code}' -o /dev/null -v -G "$HTTP://$HOST/a/6/at/$search_slot_id")
if [ "$atlas_status_code" != "200" ]; then
  echo "expected 200 from atlas, got $atlas_status_code"
  exit 1
fi

first_video_slot_id=$(echo "$result" | jq -r '.search_results[] | select(.type == "video") | .slot_id' | head -n 1)
echo "got slot $first_video_slot_id"

check_slot "$first_video_slot_id"

nextpage_slot_id=$(echo "$result" | jq -r '.nextpage_slot_id')
if [ "$nextpage_slot_id" != "null" ]; then
  nextpage_result=$(curl -A 'UnityWebRequest' -v -G "$HTTP://$HOST/a/6/r/$nextpage_slot_id")

  nextpage_video_slot_id=$(echo "$nextpage_result" | jq -r '.search_results[] | select(.type == "video") | .slot_id' | head -n 1)
  echo "got video slot from nextpage $nextpage_video_slot_id"
  if [ "$first_video_slot_id" = "$nextpage_video_slot_id" ]; then
    echo "expected first_video_slot_id and nextpage_video_slot_id to be different, but they aren't"
    exit 1
  fi
  check_slot "$nextpage_video_slot_id"
else
  echo "no nextpage slot id, ignoring that test rn"
fi

echo "pass!"
