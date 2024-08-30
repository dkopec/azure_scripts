#region USER VARIABLES
export RECOVERY_POINT_TIME="your_recovery_point_time"
export SUBSCRIPTION_ID="your_subscription_id"
export RESOURCE_GROUP="your_resource_group"
export VAULT_NAME="your_vault_name"
export BACKUP_INSTANCE_NAME="your_backup_instance_name"
export STORAGE_URL="your_storage_url"
export FILE_PREFIX="your_file_prefix"
export RESTORE_LOCATION="your_restore_location"
#endregion

export LIST_BACKUPVAULTS="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataProtection/backupVaults?api-version=2021-07-01"
export LIST_BACKUPINSTANCES="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataProtection/backupVaults/${VAULT_NAME}/backupInstances/?api-version=2021-07-01"
export BACKUP_INSTANCE_ACTUAL_NAME=$(az rest --method get --url $LIST_BACKUPINSTANCES --query "value[?properties.friendlyName=='${BACKUP_INSTANCE_NAME}'].name" -o tsv)
export LIST_RECOVERYPOINTS="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataProtection/backupVaults/${VAULT_NAME}/backupInstances/${BACKUP_INSTANCE_ACTUAL_NAME}/recoveryPoints?api-version=2021-07-01"
export RECOVERY_POINT_ID=$(az rest --method get --url $LIST_RECOVERYPOINTS --query "max_by(value[*],&properties.recoveryPointTime).properties.recoveryPointId" -o tsv)

if [ "$RECOVERY_POINT_TIME" != "latest" ]; then
  export RECOVERY_POINT_ID=$(az rest --method get --url $LIST_RECOVERYPOINTS --query "value[?properties.recoveryPointTime=='${RECOVERY_POINT_TIME}'].properties.recoveryPointId" -o tsv)
  echo "Set the Recovery point to $RECOVERY_POINT_ID taken at $RECOVERY_POINT_TIME"
fi

export VALIDATE_RESTORE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataProtection/backupVaults/${VAULT_NAME}/backupInstances/${BACKUP_INSTANCE_ACTUAL_NAME}/validateRestore?api-version=2021-07-01"

printf '{
  "objectType": "ValidateRestoreRequestObject",
  "restoreRequestObject": {
    "objectType": "AzureBackupRecoveryPointBasedRestoreRequest",
    "sourceDataStoreType": "VaultStore",
    "restoreTargetInfo": {
      "targetDetails": {
        "url": "%s",
        "filePrefix": "%s",
        "restoreTargetLocationType": "AzureBlobs"
      },
      "restoreLocation": "%s",
      "recoveryOption": "FailIfExists",
      "objectType": "RestoreFilesTargetInfo"
    },
    "recoveryPointId": "%s"
  }
}' "$STORAGE_URL" "$FILE_PREFIX" "$RESTORE_LOCATION" "$RECOVERY_POINT_ID" >test.json

az rest --method post --url $VALIDATE_RESTORE --body @test.json --debug 2>debug_verification.txt

export TRIGGER_RESTORE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataProtection/backupVaults/${VAULT_NAME}/backupInstances/${BACKUP_INSTANCE_ACTUAL_NAME}/restore?api-version=2021-07-01"

printf '{
  "objectType": "AzureBackupRecoveryPointBasedRestoreRequest",
  "sourceDataStoreType": "VaultStore",
  "restoreTargetInfo": {
    "targetDetails": {
        "url": "%s",
        "filePrefix": "%s",
        "restoreTargetLocationType": "AzureBlobs"
    },
    "restoreLocation": "%s",
    "recoveryOption": "FailIfExists",
    "objectType": "RestoreFilesTargetInfo"
  },
  "recoveryPointId": "%s"
}' "$STORAGE_URL" "$FILE_PREFIX" "$RESTORE_LOCATION" "$RECOVERY_POINT_ID" > request.json

az rest --method post --url "$TRIGGER_RESTORE" --body @request.json --debug 2>debug_request.txt

export RESULT_ASYNC_URL=$(grep -oP "'Azure-AsyncOperation': '\K\S+" "./debug_request.txt" | sed "s/'$//")

succeeded=false

while [ "$succeeded" != "Succeeded" ]; do
  succeeded=$(az rest --method get --url $RESULT_ASYNC_URL | grep -oP '"status": "\K[^"]+')
  echo "Restore request status is: $succeeded"
  # Check the value of succeeded
  if [ "$succeeded" == "Failed" ] || [ "$succeeded" == "Canceled" ]; then
    echo "Error: Restore request $succeeded"
    exit 1
  fi
  sleep 10 # Wait for a second before checking again
done

export JOB_URL="https://management.azure.com$(az rest --method get --url $RESULT_ASYNC_URL | grep -oP '"jobId": "\K[^"]+')?api-version=2021-07-01"

job_status=false

while [ "$job_status" != "Completed" ]; do
  job_status=$(az rest --method get --url $JOB_URL | grep -oP '"status": "\K[^"]+')
  echo "Restore job status is: $job_status"
  if [ "$job_status" == "Failed" ] || [ "$job_status" == "Canceled" ] || [ "$job_status" == "SuccessWithWarning" ]; then
    echo "Error: Restore request $job_status"
    exit 1
  fi
  sleep 10 # Wait for a second before checking again
done
