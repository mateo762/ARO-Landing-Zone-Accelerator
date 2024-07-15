#!/bin/bash

# TODO add hash

# ---------------------------------------------------------------------------- #
#                                   FUNCTIONS                                  #
# ---------------------------------------------------------------------------- #

display_message() {
  local message_type=$1
  local message=$2

  case $message_type in
    "error")
      echo -e "\e[31mERROR: $message\e[0m"
      ;;
    "success")
      echo -e "\e[32m$message\e[0m"
      ;;
    "warning")
      echo -e "\e[33mWARNING: $message\e[0m"
      ;;
    "info")
    echo "INFO: $message"
      ;;
    "progress")
      echo -e "\e[34m$message\e[0m" # Blue for progress
      ;;
    *)
      echo "$message"
      ;;
  esac
}

display_progress() {
  local message=$1
  display_message progress "$message"
}

display_blank_line() {
  echo ""
}

get_short_location() {
    # Read JSON with all the locations
    local locations=$(cat ./commonModules/naming/locations.json)
    # Get the short location where the input is the key and the short location is the value
    local short_location=$(echo $locations | jq -r ".$1")
    echo $short_location
}

# ---------------------------------------------------------------------------- #
#                             INTRODUCTION MESSAGE                             #
# ---------------------------------------------------------------------------- #

display_blank_line
display_progress "Deploying the Secure Baseline scenario for Azure Red Hat Openshift"

# ---------------------------------------------------------------------------- #
#                                  PARAMETERS                                  #
# ---------------------------------------------------------------------------- #

HUB_WORKLOAD_NAME=${HUB_WORKLOAD_NAME:-"hub"}
SPOKE_WORKLOAD_NAME=${SPOKE_WORKLOAD_NAME:-"aro-lza"}
ENVIRONMENT=${ENVIRONMENT:-"DEV"}
LOCATION=${LOCATION:-"eastus"}

_environment_lower_case=$(echo $ENVIRONMENT | tr '[:upper:]' '[:lower:]')
_short_location=$(get_short_location $LOCATION)

display_message info "Hub workload name: $HUB_WORKLOAD_NAME"
display_message info "Spoke workload name: $SPOKE_WORKLOAD_NAME"
display_message info "Environment: $ENVIRONMENT"
display_message info "Location: $LOCATION"
display_blank_line

# ---------------------------------------------------------------------------- #
#                                      HUB                                     #
# ---------------------------------------------------------------------------- #

# Deploy the hub resources
_hub_deployment_name="$HUB_WORKLOAD_NAME-$_environment_lower_case-$_short_location"
display_progress "Deploying the hub resources"
display_message info "Deployment name: $_hub_deployment_name"
az deployment sub create \
    --name $_hub_deployment_name \
    --location $LOCATION \
    --template-file "./01-Hub/main.bicep" \
    --parameters \
        workloadName=$HUB_WORKLOAD_NAME \
        env=$ENVIRONMENT \
        location=$LOCATION

# Get the outputs from the hub deployment
HUB_RG_NAME=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.resourceGroupName.value" -o tsv)
HUB_VNET_ID=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.virtualNetworkResourceId.value" -o tsv)
LOG_ANALYTICS_WORKSPACE_ID=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.logAnalyticsWorkspaceResourceId.value" -o tsv)
KEY_VAULT_PRIVATE_DNS_ZONE_RESOURCE_ID=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.keyVaultPrivateDnsZoneResourceId.value" -o tsv)
KEY_VAULT_PRIVATE_DNS_ZONE_NAME=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.keyVaultPrivateDnsZoneName.value" -o tsv)
ACR_PRIVATE_DNS_ZONE_RESOURCE_ID=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.acrPrivateDnsZoneResourceId.value" -o tsv)
ACR_PRIVATE_DNS_ZONE_NAME=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.acrPrivateDnsZoneName.value" -o tsv)
FIREWALL_PRIVATE_IP=$(az deployment sub show --name "$_hub_deployment_name" --query "properties.outputs.firewallPrivateIp.value" -o tsv)
display_progress "Hub resources deployed successfully"
display_blank_line

# ---------------------------------------------------------------------------- #
#                                     SPOKE                                    #
# ---------------------------------------------------------------------------- #

# Deploy the spoke network resources
_spoke_network_deployment_name="$SPOKE_WORKLOAD_NAME-$_environment_lower_case-$_short_location"
display_progress "Deploying the spoke network resources"
display_message info "Deployment name: $_spoke_network_deployment_name"
az deployment sub create \
    --name $_spoke_network_deployment_name \
    --location $LOCATION \
    --template-file "./02-Spoke/main.bicep" \
    --parameters \
        workloadName=$SPOKE_WORKLOAD_NAME \
        env=$ENVIRONMENT \
        location=$LOCATION \
        hubVirtualNetworkResourceId=$HUB_VNET_ID \
        logAnalyticsWorkspaceResourceId=$LOG_ANALYTICS_WORKSPACE_ID \
        firewallPrivateIp=$FIREWALL_PRIVATE_IP

# Get the outputs from the spoke network deployment
SPOKE_VNET_ID=$(az deployment sub show --name "$_spoke_network_deployment_name" --query "properties.outputs.virtualNetworkResourceId.value" -o tsv)
PRIVATE_ENDPOINTS_SUBNET_RESOURCE_ID=$(az deployment sub show --name "$_spoke_network_deployment_name" --query "properties.outputs.privateEndpointsSubnetResourceId.value" -o tsv)
display_progress "Spoke network resources deployed successfully"
display_blank_line

# Link spoke virtual network to private DNS zones
display_progress "Linking spoke virtual network to private DNS zones"
az deployment group create \
    --name "$SPOKE_WORKLOAD_NAME-$_environment_lower_case-link-keyvault-private-dns-to-spoke-network" \
    --resource-group $HUB_RG_NAME \
    --template-file "./02-Spoke/link-private-dns-to-spoke-network.bicep" \
    --parameters \
        workloadName=$SPOKE_WORKLOAD_NAME \
        env=$ENVIRONMENT \
        privateDnsZoneName=$KEY_VAULT_PRIVATE_DNS_ZONE_NAME \
        virtualNetworkResourceId=$SPOKE_VNET_ID
az deployment group create \
    --name "$SPOKE_WORKLOAD_NAME-$_environment_lower_case-link-acr-private-dns-to-spoke-network" \
    --resource-group $HUB_RG_NAME \
    --template-file "./02-Spoke/link-private-dns-to-spoke-network.bicep" \
    --parameters \
        workloadName=$SPOKE_WORKLOAD_NAME \
        env=$ENVIRONMENT \
        privateDnsZoneName=$ACR_PRIVATE_DNS_ZONE_NAME \
        virtualNetworkResourceId=$SPOKE_VNET_ID
display_progress "Spoke virtual network linked to private DNS zones"
display_blank_line

# Deploy the supporting services in the spoke
_spoke_services_deployment_name="$SPOKE_WORKLOAD_NAME-$_environment_lower_case-$_short_location-services"
display_progress "Deploying the supporting services in the spoke"
display_message info "Deployment name: $_spoke_services_deployment_name"
az deployment group create \
    --name $_spoke_services_deployment_name \
    --resource-group $HUB_RG_NAME \
    --template-file "./02-Spoke/services.bicep" \
    --parameters \
        workloadName=$SPOKE_WORKLOAD_NAME \
        env=$ENVIRONMENT \
        location=$LOCATION \
        privateEndpointSubnetResourceId=$PRIVATE_ENDPOINTS_SUBNET_RESOURCE_ID \
        keyVaultPrivateDnsZoneResourceId=$KEY_VAULT_PRIVATE_DNS_ZONE_RESOURCE_ID \
        logAnalyticsWorkspaceResourceId=$LOG_ANALYTICS_WORKSPACE_ID
display_progress "Supporting services in the spoke deployed successfully"
display_blank_line