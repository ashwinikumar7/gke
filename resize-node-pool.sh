#!/bin/bash

# set -x

PROJECT_ID="gcp-project-id"
REGION="region-code"
DEFAULT_STEP=50
DEFAULT_SLEEP_TIME=300

echo "Select the GKE cluster to resize the node pools:"
echo "[1] cluster-1"
echo "[2] cluster-2"
read -p "Enter your choice [1 or 2]: " choice

case "$choice" in
1)
  CLUSTER_NAME="cluster-1"
  ;;
2)
  CLUSTER_NAME="cluster-2"
  ;;
*)
  echo "Invalid choice. Exiting."
  exit 1
  ;;
esac

read -p "Enter the step size for resizing the node pools (default is $DEFAULT_STEP): " STEP
STEP=${STEP:-$DEFAULT_STEP}
if ! [[ "$STEP" =~ ^[0-9]+$ ]]; then
  echo "Invalid step size. Please enter a positive integer."
  exit 1
fi

read -p "Enter the time break between two consecutive resize request in seconds (default is $DEFAULT_SLEEP_TIME): " SLEEP_TIME
SLEEP_TIME=${SLEEP_TIME:-$DEFAULT_SLEEP_TIME}
if ! [[ "$SLEEP_TIME" =~ ^[0-9]+$ ]]; then
  echo "Invalid time. Please enter a positive integer in seconds."
  exit 1
fi


node_pools=$(gcloud container node-pools list --cluster "$CLUSTER_NAME" --location "$REGION" \
  --filter="name~node-pool-name-to-filter" \
  --format="value(name)" --project "$PROJECT_ID")

for node_pool in $node_pools; do
  echo "Processing node pool = $node_pool"

  instance_group_info=$(gcloud container node-pools describe "$node_pool" --cluster "$CLUSTER_NAME" --location "$REGION" \
    --format="value(instanceGroupUrls[0])")
  instance_group=$(echo "$instance_group_info" | cut -d "/" -f 11)
  instance_group_zone=$(echo "$instance_group_info" | cut -d "/" -f 9)

  echo "Instance group = $instance_group"

  while true; do
    current_size=$(gcloud compute instance-groups managed describe "$instance_group" \
      --zone "$instance_group_zone" --format="value(targetSize)")
    echo "Current size of node pool $node_pool = $current_size"

    if [ "$current_size" -le 0 ]; then
      break
    fi

    new_size=$((current_size - STEP))
    if [ "$new_size" -le 0 ]; then
      new_size=0
    fi

    echo "Resizing $node_pool from $current_size to $new_size"
    gcloud container clusters resize "$CLUSTER_NAME" --node-pool "$node_pool" \
      --num-nodes "$new_size" --location "$REGION" --project "$PROJECT_ID" --quiet

    if [ $? -ne 0 ]; then
      echo "Failed to resize node pool $node_pool. Exiting."
      exit 1
    fi

    echo "Resize request executed successfully at $(date)"
    sleep $SLEEP_TIME
  done
  echo "Finished resizing node pool: $node_pool"
  echo "------------------------------------------------------------------"
done

echo "All specified node pools have been resized."
