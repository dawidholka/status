#!/bin/bash

studentName=${1:?"Error: parameter missing Student Name"}
subscriptionId=${2:?"Error: parameter missing Subscription Id"}
KEY_VAULT_NAME=${3:?"Error: parameter missing Key Vault Name"}

SERVICE_PRINCIPAL_NAME="$studentName-aks-secret-store"

# Login to Azure
az login --tenant chmurowiskolab.onmicrosoft.com
az account set --subscription "$subscriptionId"

echo "Checking if service principal $SERVICE_PRINCIPAL_NAME exists..."
SERVICE_PRINCIPAL_EXISTS=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query [].appId -o tsv)
if [ -z "$SERVICE_PRINCIPAL_EXISTS" ]; then
    echo "Service principal $SERVICE_PRINCIPAL_NAME does not exist. Creating..."
    az ad sp create-for-rbac --name "$SERVICE_PRINCIPAL_NAME" -o none
else
    echo "Service principal $SERVICE_PRINCIPAL_NAME already exists. Skipping..."
fi
SERVICE_PRINCIPAL_APP_ID=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[].appId" -o tsv)
SERVICE_PRINCIPAL_OBJECT_ID=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[].id" -o tsv)
SERVICE_PRINCIPAL_APP_PASSWORD=$(az ad sp credential reset --id "$SERVICE_PRINCIPAL_APP_ID" --display-name "AKS Secret Store" --append --query password -o tsv)

echo "SERVICE_PRINCIPAL_APP_ID: $SERVICE_PRINCIPAL_APP_ID"
echo "SERVICE_PRINCIPAL_OBJECT_ID: $SERVICE_PRINCIPAL_OBJECT_ID"
echo "Checking if service principal $SERVICE_PRINCIPAL_NAME has permissions to access key vault $KEY_VAULT_NAME..."
KEY_VAULT_PERMISSIONS_EXISTS=$(az keyvault show --name "$KEY_VAULT_NAME" --query "properties.accessPolicies[?objectId=='$SERVICE_PRINCIPAL_OBJECT_ID'].permissions" -o tsv)
if [ -z "$KEY_VAULT_PERMISSIONS_EXISTS" ]; then
    echo "Service principal $SERVICE_PRINCIPAL_NAME does not have permissions to access key vault $KEY_VAULT_NAME. Granting..."
    az keyvault set-policy -n "$KEY_VAULT_NAME" \
        --secret-permissions get \
        --key-permissions get \
        --certificate-permissions get \
        --spn "$SERVICE_PRINCIPAL_APP_ID" -o none
else
    echo "Service principal $SERVICE_PRINCIPAL_NAME already has permissions to access key vault $KEY_VAULT_NAME. Skipping..."
fi

K8S_SECRET_EXISTS=$(kubectl get secret keyvault-credentials -o jsonpath="{.metadata.name}")
if [ -z "$K8S_SECRET_EXISTS" ]; then
    echo "Creating k8s secret keyvault-credentials..."
    kubectl create secret generic keyvault-credentials \
        --from-literal clientid="$SERVICE_PRINCIPAL_APP_ID" \
        --from-literal clientsecret="$SERVICE_PRINCIPAL_APP_PASSWORD"
else
    echo "Updating k8s secret keyvault-credentials..."
    kubectl delete secret keyvault-credentials
    kubectl create secret generic keyvault-credentials \
        --from-literal clientid="$SERVICE_PRINCIPAL_APP_ID" \
        --from-literal clientsecret="$SERVICE_PRINCIPAL_APP_PASSWORD"
fi
kubectl label secret keyvault-credentials \
    secrets-store.csi.k8s.io/used=true
