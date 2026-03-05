# Deploy Apache Airflow on AKS with Helm
- [Deploy Apache Airflow on AKS with Helm](#deploy-apache-airflow-on-aks-with-helm)
  - [What is Apache Airflow?](#what-is-apache-airflow)
  - [Airflow architecture](#airflow-architecture)
  - [Airflow distributed architecture for production](#airflow-distributed-architecture-for-production)
    - [Airflow executors](#airflow-executors)
- [Create infrastructure for deploying Apache Airflow on AKS](#create-infrastructure-for-deploying-apache-airflow-on-aks)
  - [Prerequisites](#prerequisites)
  - [Set environment variables](#set-environment-variables)
  - [Create a resource group](#create-a-resource-group)
  - [Create an identity to access secrets in Azure Key Vault](#create-an-identity-to-access-secrets-in-azure-key-vault)
  - [Create an Azure Key Vault instance](#create-an-azure-key-vault-instance)
  - [Create an Azure container registry](#create-an-azure-container-registry)
  - [Create an Azure storage account](#create-an-azure-storage-account)
  - [Create an AKS cluster](#create-an-aks-cluster)
  - [Connect to the AKS cluster](#connect-to-the-aks-cluster)
  - [Upload Apache Airflow images to your container registry](#upload-apache-airflow-images-to-your-container-registry)
- [Configure and deploy Apache Airflow on AKS using Helm](#configure-and-deploy-apache-airflow-on-aks-using-helm)
  - [Configure workload identity](#configure-workload-identity)
  - [Install the External Secrets Operator](#install-the-external-secrets-operator)
    - [Create secrets](#create-secrets)
  - [Create a persistent volume for Apache Airflow logs](#create-a-persistent-volume-for-apache-airflow-logs)
  - [Create a persistent volume claim for Apache Airflow logs](#create-a-persistent-volume-claim-for-apache-airflow-logs)
  - [Deploy Apache Airflow using Helm](#deploy-apache-airflow-using-helm)
  - [Access Airflow UI](#access-airflow-ui)
  - [Integrate Git with Airflow](#integrate-git-with-airflow)
  - [Make your Airflow on Kubernetes production-grade](#make-your-airflow-on-kubernetes-production-grade)
- [Create infrastructure for deploying a PostgreSQL database on AKS](#create-infrastructure-for-deploying-a-postgresql-database-on-aks)
  - [Before you begin](#before-you-begin)
  - [Set environment variables](#set-environment-variables-1)
  - [Install required extensions](#install-required-extensions)
  - [Create a resource group](#create-a-resource-group-1)
  - [Create a user-assigned managed identity](#create-a-user-assigned-managed-identity)
  - [Create a storage account in the primary region](#create-a-storage-account-in-the-primary-region)
  - [Assign RBAC to storage accounts](#assign-rbac-to-storage-accounts)
  - [Set up monitoring infrastructure](#set-up-monitoring-infrastructure)
  - [Create the AKS cluster to host the PostgreSQL cluster](#create-the-aks-cluster-to-host-the-postgresql-cluster)
  - [Connect to the AKS cluster and create namespaces](#connect-to-the-aks-cluster-and-create-namespaces)
  - [Update the monitoring infrastructure](#update-the-monitoring-infrastructure)
  - [Create a public static IP for PostgreSQL cluster ingress](#create-a-public-static-ip-for-postgresql-cluster-ingress)
  - [Install the CNPG operator in the AKS cluster](#install-the-cnpg-operator-in-the-aks-cluster)
- [Deploy a highly available PostgreSQL database on AKS](#deploy-a-highly-available-postgresql-database-on-aks)
  - [Create secret for bootstrap app user](#create-secret-for-bootstrap-app-user)
  - [Set environment variables for the PostgreSQL cluster](#set-environment-variables-for-the-postgresql-cluster)
  - [Install the Prometheus PodMonitors](#install-the-prometheus-podmonitors)
  - [Create a federated credential](#create-a-federated-credential)
  - [Deploy a highly available PostgreSQL cluster](#deploy-a-highly-available-postgresql-cluster)
    - [Cluster CRD parameters](#cluster-crd-parameters)
    - [PostgreSQL performance parameters](#postgresql-performance-parameters)
    - [Deploying PostgreSQL](#deploying-postgresql)
  - [Validate the Prometheus PodMonitor is running](#validate-the-prometheus-podmonitor-is-running)
    - [Option A - Azure Monitor workspace](#option-a---azure-monitor-workspace)
    - [Option B - Managed Grafana](#option-b---managed-grafana)
- [Cloud Native](#cloud-native)




In this guide, you deploy Apache Airflow on Azure Kubernetes Service (AKS) using Helm. You learn how to set up an AKS cluster, install Helm, deploy Airflow using the Helm chart, and explore the Airflow UI. This article provides a high-level overview of the architecture and components involved in deploying production-ready Airflow on AKS.

Important

Open-source software is mentioned throughout AKS documentation and samples. Software that you deploy is excluded from AKS service-level agreements, limited warranty, and Azure support. As you use open-source technology alongside AKS, consult the support options available from the respective communities and project maintainers to develop a plan.

Microsoft takes responsibility for building the open-source packages that we deploy on AKS. That responsibility includes having complete ownership of the build, scan, sign, validate, and hotfix process, along with control over the binaries in container images. For more information, see [Vulnerability management for AKS](concepts-vulnerability-management#aks-container-images) and [AKS support coverage](support-policies#aks-support-coverage).

## What is Apache Airflow?

[Apache Airflow](https://airflow.apache.org/) is an open-source platform built for developing, scheduling, and monitoring batch-oriented workflows. With its flexible Python framework, Airflow allows you to design workflows that integrate seamlessly with nearly any technology. In Airflow, you must define Python workflows, represented by Directed Acyclic Graph (DAG). You can deploy Airflow anywhere, and after deploying, you can access Airflow UI and set up workflows.

## Airflow architecture

At a high level, Airflow includes:

- A metadata database that tracks the state of DAGs, task instances, XComs, and more.
- A web server providing the Airflow UI for monitoring and management.
- A scheduler responsible for triggering DAGs and task instances.
- Executors that handle the execution of task instances.
- Workers that perform the tasks.
- Other components like the Command Line Interface (CLI).

![Architecture diagram of Apache Airflow on AKS.](airflow-architecture.png)

## Airflow distributed architecture for production

Airflow’s modular, distributed architecture offers several key advantages for production workloads:

- **Separation of concerns**: Each component has a distinct role, keeping the system simple and maintainable. The scheduler manages DAGs and task scheduling, while workers execute tasks, ensuring that each part stays focused on its specific function.
- **Scalability**: As workloads grow, the architecture allows for easy scaling. You can run multiple schedulers or workers concurrently and leverage a hosted database for automatic scaling to accommodate increased demand.
- **Reliability**: Because components are decoupled, the failure of a single scheduler or worker doesn’t lead to a system-wide outage. The centralized metadata database ensures consistency and continuity across the entire system.
- **Extensibility**: The architecture is flexible, allowing components like the executor or queueing service to be swapped out and customized as needed.

This design provides a robust foundation for scaling, reliability, and flexibility in managing complex data pipelines.

### Airflow executors

A very important design decision when making Airflow production-ready is choosing the correct executor. When a task is ready to run, the executor is responsible for managing its execution. Executors interact with a pool of workers that carry out the tasks. The most commonly used executors are:

- **LocalExecutor**: Runs task instances in parallel on the host system. This executor is ideal for testing, but offers limited scalability for larger workloads.
- **CeleryExecutor**: Distributes tasks across multiple machines using a Celery pool, providing horizontal scalability by running workers on different nodes.
- **KubernetesExecutor**: Tailored for Airflow deployments in Kubernetes, this executor dynamically launches worker Pods within the Kubernetes cluster. It offers excellent scalability and ensures strong resource isolation.

As we transition Airflow to production, scaling workers becomes essential, making KubernetesExecutor the best fit for our needs. For local testing, however, LocalExecutor is the simplest option.

---

# Create infrastructure for deploying Apache Airflow on AKS

In this article, you create the infrastructure resources needed to run Apache Airflow on Azure Kubernetes Service (AKS).

## Prerequisites

- If you haven't already, review the [Overview for deploying an Apache Airflow cluster on Azure Kubernetes Service (AKS)](airflow-overview).
- An Azure subscription. If you don't have one, create a [free account](https://azure.microsoft.com/pricing/purchase-options/azure-account?cid=msft_learn).
- Azure CLI version 2.61.0. To install or upgrade, see [Install Azure CLI](/en-us/cli/azure/install-azure-cli).
- Helm version 3 or later. To install, see [Installing Helm](https://helm.sh/docs/intro/install/).
- `kubectl`, which is installed in Azure Cloud Shell by default.
- GitHub Repo to store Airflow Dags.
- Docker installed on your local machine. To install, see [Get Docker](https://docs.docker.com/get-docker/).

## Set environment variables

- Set the required environment variables for use throughout this guide:

    ```bash
    random=$(echo $RANDOM | tr '[0-9]' '[a-z]')
    export MY_LOCATION=canadacentral
    export MY_RESOURCE_GROUP_NAME=apache-airflow-rg
    export MY_IDENTITY_NAME=airflow-identity-123
    export MY_ACR_REGISTRY=mydnsrandomname$(echo $random)
    export MY_KEYVAULT_NAME=airflow-vault-$(echo $random)-kv
    export MY_CLUSTER_NAME=apache-airflow-aks
    export SERVICE_ACCOUNT_NAME=airflow
    export SERVICE_ACCOUNT_NAMESPACE=airflow
    export AKS_AIRFLOW_NAMESPACE=airflow
    export AKS_AIRFLOW_CLUSTER_NAME=cluster-aks-airflow
    export AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME=airflowsasa$(echo $random)
    export AKS_AIRFLOW_LOGS_STORAGE_CONTAINER_NAME=airflow-logs
    export AKS_AIRFLOW_LOGS_STORAGE_SECRET_NAME=storage-account-credentials
    ```

## Create a resource group

- Create a resource group using the [`az group create`](/en-us/cli/azure/group#az-group-create) command.

    ```sh
    az group create --name $MY_RESOURCE_GROUP_NAME --location $MY_LOCATION --output table
    ```

    Example output:

    ```output
    Location       Name
    -------------  -----------------
    $MY_LOCATION   $MY_RESOURCE_GROUP_NAME
    ```

## Create an identity to access secrets in Azure Key Vault

In this step, we create a user-assigned managed identity that the External Secrets Operator uses to access the Airflow passwords stored in Azure Key Vault.

- Create a user-assigned managed identity using the [`az identity create`](/en-us/cli/azure/identity#az-identity-create) command.

    ```sh
    az identity create --name $MY_IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --output table

    export MY_IDENTITY_NAME_ID=$(az identity show --name $MY_IDENTITY_NAME \
                                                  --resource-group $MY_RESOURCE_GROUP_NAME \
                                                  --query id --output tsv)

    export MY_IDENTITY_NAME_PRINCIPAL_ID=$(az identity show --name $MY_IDENTITY_NAME \
                                                            --resource-group $MY_RESOURCE_GROUP_NAME \
                                                            --query principalId --output tsv)

    export MY_IDENTITY_NAME_CLIENT_ID=$(az identity show --name $MY_IDENTITY_NAME \
                                                         --resource-group $MY_RESOURCE_GROUP_NAME \
                                                         --query clientId --output tsv)
    ```

    Example output:

    ```text
    ClientId                              Location       Name                  PrincipalId                           ResourceGroup            TenantId
    ------------------------------------  -------------  --------------------  ------------------------------------  -----------------------  ------------------------------------  
    00001111-aaaa-2222-bbbb-3333cccc4444  $MY_LOCATION   $MY_IDENTITY_NAME     aaaaaaaa-bbbb-cccc-1111-222222222222  $MY_RESOURCE_GROUP_NAME  aaaabbbb-0000-cccc-1111-dddd2222eeee 
    ```

## Create an Azure Key Vault instance

- Create an Azure Key Vault instance using the [`az keyvault create`](/en-us/cli/azure/keyvault#az-keyvault-create) command.

    ```sh
    az keyvault create --name $MY_KEYVAULT_NAME --resource-group $MY_RESOURCE_GROUP_NAME --location $MY_LOCATION --enable-rbac-authorization false --output table
    export KEYVAULTID=$(az keyvault show --name $MY_KEYVAULT_NAME --query "id" --output tsv)
    export KEYVAULTURL=$(az keyvault show --name $MY_KEYVAULT_NAME --query "properties.vaultUri" --output tsv)
    ```

    Example output:

    ```output
    Location       Name                  ResourceGroup
    -------------  --------------------  ----------------------
    $MY_LOCATION   $MY_KEYVAULT_NAME     $MY_RESOURCE_GROUP_NAME
    ```

## Create an Azure container registry

- Create an Azure container registry to store and manage your container images using the [`az acr create`](/en-us/cli/azure/acr#az-acr-create) command.

    ```sh
    az acr create \
    --name ${MY_ACR_REGISTRY} \
    --resource-group $MY_RESOURCE_GROUP_NAME \
    --sku Premium \
    --location $MY_LOCATION \
    --admin-enabled true \
    --output table
    export MY_ACR_REGISTRY_ID=$(az acr show --name $MY_ACR_REGISTRY --resource-group $MY_RESOURCE_GROUP_NAME --query id --output tsv)
    ```

    Example output:

    ```output
    NAME                  RESOURCE GROUP           LOCATION       SKU      LOGIN SERVER                     CREATION DATE         ADMIN ENABLED
    --------------------  ----------------------   -------------  -------  -------------------------------  --------------------  ---------------
    mydnsrandomnamebfbje  $MY_RESOURCE_GROUP_NAME  $MY_LOCATION   Premium  mydnsrandomnamebfbje.azurecr.io  2024-11-07T00:32:48Z  True
    ```

## Create an Azure storage account

- Create an Azure Storage Account to store the Airflow logs using the [`az acr create`](/en-us/cli/azure/storage/account#az-storage-account-create) command.

    ```sh
    az storage account create --name $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME --resource-group $MY_RESOURCE_GROUP_NAME --location $MY_LOCATION --sku Standard_ZRS --output table
    export AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_KEY=$(az storage account keys list --account-name $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME --query "[0].value" -o tsv)
    az storage container create --name $AKS_AIRFLOW_LOGS_STORAGE_CONTAINER_NAME --account-name $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME --output table --account-key $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_KEY
    az keyvault secret set --vault-name $MY_KEYVAULT_NAME --name AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-NAME --value $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME
    az keyvault secret set --vault-name $MY_KEYVAULT_NAME --name AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-KEY --value $AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_KEY
    ```

    Example output:

    ```sh
    AccessTier    AllowBlobPublicAccess    AllowCrossTenantReplication    CreationTime                      EnableHttpsTrafficOnly    Kind       Location       MinimumTlsVersion    Name              PrimaryLocation    ProvisioningState    ResourceGroup      StatusOfPrimary
    ------------  -----------------------  -----------------------------  --------------------------------  ------------------------  ---------  -------------  -------------------  ----------------  -----------------  -------------------  -----------------  -----------------
    Hot           False                    False                          2024-11-07T00:22:13.323104+00:00  True                      StorageV2  $MY_LOCATION   TLS1_0               airflowsasabfbje  $MY_LOCATION       Succeeded            $MY_RESOURCE_GROUP_NAME  available
    Created
    ---------
    True
    ```

## Create an AKS cluster

In this step, we create an AKS cluster with workload identity and OIDC issuer enabled. This configuration creates a high-availability AKS cluster optimized for running production workloads like Apache Airflow. It provisions a *three* node cluster using `Standard_DS4_v2` VMs across three availability zones for resilience. The cluster is integrated with ACR for secure image pulls and includes OIDC issuer and workload identity support for secure, identity-based access to Azure resources. It also enables the Azure CNI network plugin, Blob CSI driver, and automatic node OS and Kubernetes version upgrades for enhanced performance and security.

1. Create an AKS cluster using the [`az aks create`](/en-us/cli/azure/aks#az-aks-create) command.

    ```sh
    az aks create \
    --location $MY_LOCATION \
    --name $MY_CLUSTER_NAME \
    --tier standard \
    --resource-group $MY_RESOURCE_GROUP_NAME \
    --network-plugin azure  \
    --node-vm-size Standard_DS4_v2 \
    --node-count 3 \
    --auto-upgrade-channel stable \
    --node-os-upgrade-channel NodeImage \
    --attach-acr ${MY_ACR_REGISTRY} \
    --enable-oidc-issuer \
    --enable-blob-driver \
    --enable-workload-identity \
    --zones 1 2 3 \
    --generate-ssh-keys \
    --output table
    ```

    Example output:

    ```output
    AzurePortalFqdn                                                                 CurrentKubernetesVersion    DisableLocalAccounts    DnsPrefix                           EnableRbac    Fqdn                                                                     KubernetesVersion    Location       MaxAgentPools    Name                NodeResourceGroup                                      ProvisioningState    ResourceGroup            ResourceUid                           SupportPlan
    ------------------------------------------------------------------------------  --------------------------  ----------------------  ----------------------------------  ------------  -----------------------------------------------------------------------  -------------------  -------------  ---------------  ------------------  -----------------------------------------------------  -------------------  -----------------------  ------------------------------------  ------------------
    apache-air-apache-airflow-r-363a0a-rhf6saad.portal.hcp.$MY_LOCATION.azmk8s.io   1.29.9                      False                   apache-air-apache-airflow-r-363a0a  True          apache-air-apache-airflow-r-363a0a-rhf6saad.hcp.$MY_LOCATION.azmk8s.io   1.29                 $MY_LOCATION   100              $MY_CLUSTER_NAME    MC_apache-airflow-rg_apache-airflow-aks_$MY_LOCATION   Succeeded            $MY_RESOURCE_GROUP_NAME  b1b1b1b1-cccc-dddd-eeee-f2f2f2f2f2f2  KubernetesOfficial
    ```
2. Get the OIDC issuer URL to use for the workload identity configuration using the [`az aks show`](/en-us/cli/azure/aks#az-aks-show) command.

    ```sh
    export OIDC_URL=$(az aks show --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_CLUSTER_NAME --query oidcIssuerProfile.issuerUrl --output tsv)
    ```
3. Assign the `AcrPull` role to the kubelet identity using the [`az role assignment create`](/en-us/cli/azure/role/assignment#az-role-assignment-create) command.

    ```sh
    export KUBELET_IDENTITY=$(az aks show -g $MY_RESOURCE_GROUP_NAME --name $MY_CLUSTER_NAME --output tsv --query identityProfile.kubeletidentity.objectId)
    az role assignment create \
    --assignee ${KUBELET_IDENTITY} \
    --role "AcrPull" \
    --scope ${MY_ACR_REGISTRY_ID} \
    --output table
    ```

    Example output:

    ```output
    CreatedBy                             CreatedOn                         Name                                  PrincipalId                           PrincipalName                         PrincipalType     ResourceGroup            RoleDefinitionId                                                                                                                            RoleDefinitionName    Scope                                                                                                                                                             UpdatedBy                             UpdatedOn
    ------------------------------------  --------------------------------  ------------------------------------  ------------------------------------  ------------------------------------  ----------------  -----------------------  ------------------------------------------------------------------------------------------------------------------------------------------  --------------------  ----------------------------------------------------------------------------------------------------------------------------------------------------------        ------------------------------------  --------------------------------
    ccccdddd-2222-eeee-3333-ffff4444aaaa  2024-11-07T00:43:26.905445+00:00  b1b1b1b1-cccc-dddd-eeee-f2f2f2f2f2f2  bbbbbbbb-cccc-dddd-2222-333333333333  cccccccc-dddd-eeee-3333-444444444444  ServicePrincipal  $MY_RESOURCE_GROUP_NAME  /subscriptions/aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d  AcrPull               /subscriptions/aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e/resourceGroups/$MY_RESOURCE_GROUP_NAME/providers/Microsoft.ContainerRegistry/registries/mydnsrandomnamebfbje  ccccdddd-2222-eeee-3333-ffff4444aaaa  2024-11-07T00:43:26.905445+00:00
    ```

## Connect to the AKS cluster

- Configure `kubectl` to connect to your AKS cluster using the [`az aks get-credentials`](/en-us/cli/azure/aks#az-aks-get-credentials) command.

    ```sh
    az aks get-credentials --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_CLUSTER_NAME --overwrite-existing --output table
    ```

## Upload Apache Airflow images to your container registry

In this section, we download the Apache Airflow images from Docker Hub and upload them to Azure Container Registry. This step ensures that the images are available in your private registry and can be used in your AKS cluster. We don't recommend consuming the public image in a production environment.

- Import the Airflow images from Docker Hub and upload them to your container registry using the [`az acr import`](/en-us/cli/azure/acr#az-acr-import) command.

    ```sh
    az acr import --name $MY_ACR_REGISTRY --source docker.io/apache/airflow:airflow-pgbouncer-2025.03.05-1.23.1 --image airflow:airflow-pgbouncer-2025.03.05-1.23.1
    az acr import --name $MY_ACR_REGISTRY --source docker.io/apache/airflow:airflow-pgbouncer-exporter-2025.03.05-0.18.0 --image airflow:airflow-pgbouncer-exporter-2025.03.05-0.18.0
    az acr import --name $MY_ACR_REGISTRY --source docker.io/bitnamilegacy/postgresql:16.1.0-debian-11-r15 --image postgresql:16.1.0-debian-11-r15
    az acr import --name $MY_ACR_REGISTRY --source quay.io/prometheus/statsd-exporter:v0.28.0 --image statsd-exporter:v0.28.0 
    az acr import --name $MY_ACR_REGISTRY --source docker.io/apache/airflow:3.0.2 --image airflow:3.0.2 
    az acr import --name $MY_ACR_REGISTRY --source registry.k8s.io/git-sync/git-sync:v4.3.0 --image git-sync:v4.3.0
    ```

---

# Configure and deploy Apache Airflow on AKS using Helm

In this article, you configure and deploy Apache Airflow on Azure Kubernetes Service (AKS) using Helm.

## Configure workload identity

1. Create a namespace for the Airflow cluster using the `kubectl create namespace` command.

    ```bash
    kubectl create namespace ${AKS_AIRFLOW_NAMESPACE} --dry-run=client --output yaml | kubectl apply -f -
    ```

    Example output:

    ```output
    namespace/airflow created
    ```
2. Create a service account and configure workload identity using the `kubectl apply` command.

    ```bash
    export TENANT_ID=$(az account show --query tenantId -o tsv)
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      annotations:
        azure.workload.identity/client-id: "${MY_IDENTITY_NAME_CLIENT_ID}"
        azure.workload.identity/tenant-id: "${TENANT_ID}"
      name: "${SERVICE_ACCOUNT_NAME}"
      namespace: "${AKS_AIRFLOW_NAMESPACE}"
    EOF
    ```

    Example output:

    ```output
    serviceaccount/airflow created
    ```

## Install the External Secrets Operator

In this section, we use Helm to install the External Secrets Operator. The External Secrets Operator is a Kubernetes operator that manages the lifecycle of external secrets stored in external secret stores like Azure Key Vault.

1. Add the External Secrets Helm repository and update the repository using the `helm repo add` and `helm repo update` commands.

    ```bash
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    ```

    Example output:

    ```output
    Hang tight while we grab the latest from your chart repositories...
    ...Successfully got an update from the "external-secrets" chart repository
    ```
2. Install the External Secrets Operator using the `helm install` command.

    ```bash
    helm install external-secrets \
    external-secrets/external-secrets \
    --namespace ${AKS_AIRFLOW_NAMESPACE} \
    --create-namespace \
    --set installCRDs=true \
    --wait
    ```

    Example output:

    ```output
    NAME: external-secrets
    LAST DEPLOYED: Thu Nov  7 11:16:07 2024
    NAMESPACE: airflow
    STATUS: deployed
    REVISION: 1
    TEST SUITE: None
    NOTES:
    external-secrets has been deployed successfully in namespace airflow!
    
    In order to begin using ExternalSecrets, you will need to set up a SecretStore
    or ClusterSecretStore resource (for example, by creating a 'vault' SecretStore).
    
    More information on the different types of SecretStores and how to configure them
    can be found in our Github: https://github.com/external-secrets/external-secrets
    ```

### Create secrets

1. Create a `SecretStore` resource to access the Airflow passwords stored in your key vault using the `kubectl apply` command.

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: external-secrets.io/v1
    kind: SecretStore
    metadata:
      name: azure-store
      namespace: ${AKS_AIRFLOW_NAMESPACE}
    spec:
      provider:
        # provider type: azure keyvault
        azurekv:
          authType: WorkloadIdentity
          vaultUrl: "${KEYVAULTURL}"
          serviceAccountRef:
            name: ${SERVICE_ACCOUNT_NAME}
    EOF
    ```

    Example output:

    ```output
    secretstore.external-secrets.io/azure-store created
    ```
2. Create an `ExternalSecret` resource, which creates a Kubernetes `Secret` in the `airflow` namespace with the `Airflow` secrets stored in your key vault, using the `kubectl apply` command.

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: airflow-aks-azure-logs-secrets
      namespace: ${AKS_AIRFLOW_NAMESPACE}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        kind: SecretStore
        name: azure-store
    
      target:
        name: ${AKS_AIRFLOW_LOGS_STORAGE_SECRET_NAME}
        creationPolicy: Owner
    
      data:
        # name of the SECRET in the Azure KV (no prefix is by default a SECRET)
        - secretKey: azurestorageaccountname
          remoteRef:
            key: AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-NAME
        - secretKey: azurestorageaccountkey
          remoteRef:
            key: AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-KEY
    EOF
    ```

    Example output:

    ```output
    externalsecret.external-secrets.io/airflow-aks-azure-logs-secrets created
    ```
3. Create a federated credential using the `az identity federated-credential create` command.

    ```bash
    az identity federated-credential create \
        --name external-secret-operator \
        --identity-name ${MY_IDENTITY_NAME} \
        --resource-group ${MY_RESOURCE_GROUP_NAME} \
        --issuer ${OIDC_URL} \
        --subject system:serviceaccount:${AKS_AIRFLOW_NAMESPACE}:${SERVICE_ACCOUNT_NAME} \
        --output table
    ```

    Example output:

    ```output
    Issuer                                                                                                                   Name                      ResourceGroup            Subject
    -----------------------------------------------------------------------------------------------------------------------  ------------------------  -----------------------  -------------------------------------
    https://$MY_LOCATION.oic.prod-aks.azure.com/c2c2c2c2-dddd-eeee-ffff-a3a3a3a3a3a3/aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e/  external-secret-operator  $MY_RESOURCE_GROUP_NAME  system:serviceaccount:airflow:airflow
    ```
4. Give permission to the user-assigned identity to access the secret using the [`az keyvault set-policy`](/en-us/cli/azure/keyvault#az-keyvault-set-policy) command.

    ```bash
    az keyvault set-policy --name $MY_KEYVAULT_NAME --object-id $MY_IDENTITY_NAME_PRINCIPAL_ID --secret-permissions get --output table
    ```

    Example output:

    ```output
    Location       Name                    ResourceGroup
    -------------  ----------------------  -----------------------
    $MY_LOCATION   $MY_KEYVAULT_NAME       $MY_RESOURCE_GROUP_NAME
    ```

## Create a persistent volume for Apache Airflow logs

- Create a persistent volume using the `kubectl apply` command.

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: pv-airflow-logs
      labels:
        type: local
    spec:
      capacity:
        storage: 5Gi
      accessModes:
        - ReadWriteMany
      persistentVolumeReclaimPolicy: Retain # If set as "Delete" container would be removed after pvc deletion
      storageClassName: azureblob-fuse-premium
      mountOptions:
        - -o allow_other
        - --file-cache-timeout-in-seconds=120
      csi:
        driver: blob.csi.azure.com
        readOnly: false
        volumeHandle: airflow-logs-1
        volumeAttributes:
          resourceGroup: ${MY_RESOURCE_GROUP_NAME}
          storageAccount: ${AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME}
          containerName: ${AKS_AIRFLOW_LOGS_STORAGE_CONTAINER_NAME}
        nodeStageSecretRef:
          name: ${AKS_AIRFLOW_LOGS_STORAGE_SECRET_NAME}
          namespace: ${AKS_AIRFLOW_NAMESPACE}
    EOF
    ```

    Example output:

    ```output
    persistentvolume/pv-airflow-logs created
    ```

## Create a persistent volume claim for Apache Airflow logs

- Create a persistent volume claim using the `kubectl apply` command.

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: pvc-airflow-logs
      namespace: ${AKS_AIRFLOW_NAMESPACE}
    spec:
      storageClassName: azureblob-fuse-premium
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 5Gi
      volumeName: pv-airflow-logs
    EOF
    ```

    Example output:

    ```output
    persistentvolumeclaim/pvc-airflow-logs created
    ```

## Deploy Apache Airflow using Helm

1. Configure an `airflow_values.yaml` file to change the default deployment configurations for the chart and update the container registry for the images.

    ```bash
    cat <<EOF> airflow_values.yaml
    
    images:
      airflow:
        repository: $MY_ACR_REGISTRY.azurecr.io/airflow
        tag: 3.0.2
        # Specifying digest takes precedence over tag.
        digest: ~
        pullPolicy: IfNotPresent
      # To avoid images with user code, you can turn this to 'true' and
      # all the 'run-airflow-migrations' and 'wait-for-airflow-migrations' containers/jobs
      # will use the images from 'defaultAirflowRepository:defaultAirflowTag' values
      # to run and wait for DB migrations .
      useDefaultImageForMigration: false
      # timeout (in seconds) for airflow-migrations to complete
      migrationsWaitTimeout: 60
      pod_template:
        # Note that `images.pod_template.repository` and `images.pod_template.tag` parameters
        # can be overridden in `config.kubernetes` section. So for these parameters to have effect
        # `config.kubernetes.worker_container_repository` and `config.kubernetes.worker_container_tag`
        # must be not set .
        repository: $MY_ACR_REGISTRY.azurecr.io/airflow
        tag: 3.0.2
        pullPolicy: IfNotPresent
      flower:
        repository: $MY_ACR_REGISTRY.azurecr.io/airflow
        tag: 3.0.2
        pullPolicy: IfNotPresent
      statsd:
        repository: $MY_ACR_REGISTRY.azurecr.io/statsd-exporter
        tag: v0.28.0
        pullPolicy: IfNotPresent
      pgbouncer:
        repository: $MY_ACR_REGISTRY.azurecr.io/airflow
        tag: airflow-pgbouncer-2025.03.05-1.23.1
        pullPolicy: IfNotPresent
      pgbouncerExporter:
        repository: $MY_ACR_REGISTRY.azurecr.io/airflow
        tag: airflow-pgbouncer-exporter-2025.03.05-0.18.0
        pullPolicy: IfNotPresent
      gitSync:
        repository: $MY_ACR_REGISTRY.azurecr.io/git-sync
        tag: v4.3.0
        pullPolicy: IfNotPresent

    # Airflow executor
    executor: "KubernetesExecutor"
    
    # Environment variables for all airflow containers
    env:
      - name: ENVIRONMENT
        value: dev
    
    extraEnv: |
      - name: AIRFLOW__CORE__DEFAULT_TIMEZONE
        value: 'America/New_York'
    
    # Configuration for postgresql subchart
    # Not recommended for production! Instead, spin up your own Postgresql server and use the `data` attribute in this
    # yaml file.
    postgresql:
      enabled: true
      image:
        registry: $MY_ACR_REGISTRY.azurecr.io
        repository: postgresql
        tag: 16.1.0-debian-11-r15
    
    # Enable pgbouncer. See https://airflow.apache.org/docs/helm-chart/stable/production-guide.html#pgbouncer
    pgbouncer:
      enabled: true
    
    dags:
      gitSync:
        enabled: true
        repo: https://github.com/donhighmsft/airflowexamples.git
        branch: main
        rev: HEAD
        depth: 1
        maxFailures: 0
        subPath: "dags"
        # sshKeySecret: airflow-git-ssh-secret
        # knownHosts: |
        #   github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
    
    logs:
      persistence:
        enabled: true
        existingClaim: pvc-airflow-logs
        storageClassName: azureblob-fuse-premium
    
    # We disable the log groomer sidecar because we use Azure Blob Storage for logs, with lifecyle policy set.
    triggerer:
      logGroomerSidecar:
        enabled: false
    
    scheduler:
      logGroomerSidecar:
        enabled: false
    
    workers:
      logGroomerSidecar:
        enabled: false
    
    EOF
    ```
2. Add the Apache Airflow Helm repository and update the repository using the `helm repo add` and `helm repo update` commands.

    ```bash
    helm repo add apache-airflow https://airflow.apache.org
    helm repo update
    ```

    Example output:

    ```output
    "apache-airflow" has been added to your repositories
    Hang tight while we grab the latest from your chart repositories...
    ...Successfully got an update from the "apache-airflow" chart repository
    ```
3. Search the Helm repository for the Apache Airflow chart using the `helm search repo` command.

    ```bash
    helm search repo airflow
    ```

    Example output:

    ```output
    NAME                    CHART VERSION   APP VERSION     DESCRIPTION
    apache-airflow/airflow  1.15.0          3.0.2           The official Helm chart to deploy Apache Airflo...
    ```
4. Install the Apache Airflow chart using the `helm install` command.

    ```bash
    helm install airflow apache-airflow/airflow --version 1.15.0 --namespace airflow --create-namespace -f airflow_values.yaml --debug
    ```

    Example output:

    ```output
    NAME: airflow
    LAST DEPLOYED: Fri Nov  8 11:59:43 2024
    NAMESPACE: airflow
    STATUS: deployed
    REVISION: 1
    TEST SUITE: None
    NOTES:
    Thank you for installing Apache Airflow 3.0.2!
    
    Your release is named airflow.
    You can now access your dashboard(s) by executing the following command(s) and visiting the corresponding port at localhost in your browser:
    
    Airflow Webserver:     kubectl port-forward svc/airflow-webserver 8080:8080 --namespace airflow
    Default Webserver (Airflow UI) Login credentials:
        username: admin
        password: admin
    Default Postgres connection credentials:
        username: postgres
        password: postgres
        port: 5432
    
    You can get Fernet Key value by running the following:
    
        echo Fernet Key: $(kubectl get secret --namespace airflow airflow-fernet-key -o jsonpath="{.data.fernet-key}" | base64 --decode)
    
    ###########################################################
    #  WARNING: You should set a static webserver secret key  #
    ###########################################################
    
    You are using a dynamically generated webserver secret key, which can lead to
    unnecessary restarts of your Airflow components.
    
    Information on how to set a static webserver secret key can be found here:
    https://airflow.apache.org/docs/helm-chart/stable/production-guide.html#webserver-secret-key
    ```
5. Verify the installation using the `kubectl get pods` command.

    ```bash
    kubectl get pods -n airflow
    ```

    Example output:

    ```output
    NAME                                                READY   STATUS      RESTARTS   AGE
    airflow-create-user-kklqf                           1/1     Running     0          12s
    airflow-pgbouncer-d7bf9f649-25fnt                   2/2     Running     0          61s
    airflow-postgresql-0                                1/1     Running     0          61s
    airflow-run-airflow-migrations-zns2b                0/1     Completed   0          60s
    airflow-scheduler-5c45c6dbdd-7t6hv                  1/2     Running     0          61s
    airflow-statsd-6df8564664-6rbw8                     1/1     Running     0          61s
    airflow-triggerer-0                                 2/2     Running     0          61s
    airflow-webserver-7df76f944c-vcd5s                  0/1     Running     0          61s
    external-secrets-748f44c8b8-w7qrk                   1/1     Running     0          3h6m
    external-secrets-cert-controller-57b9f4cb7c-vl4m8   1/1     Running     0          3h6m
    external-secrets-webhook-5954b69786-69rlp           1/1     Running     0          3h6m
    ```

## Access Airflow UI

1. Securely access the Airflow UI through port-forwarding using the `kubectl port-forward` command.

    ```bash
    kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
    ```
2. Open your browser and navigate to `localhost:8080` to access the Airflow UI.
3. To sign in, use the default webserver URL and sign-in credentials provided during the Airflow Helm chart installation.
4. Explore and manage your workflows securely through the Airflow UI.

## Integrate Git with Airflow

**Integrating Git with Apache Airflow** enables seamless version control and streamlined management of your workflow definitions, ensuring that all DAGs are both organized and easily auditable.

1. **Set up a Git repository for DAGs**. Create a dedicated Git repository to house all your Airflow DAG definitions. This repository serves as the central source of truth for your workflows, allowing you to manage, track, and collaborate on DAGs effectively.
2. **Configure Airflow to sync DAGs from Git**. Update Airflow's configuration to automatically pull DAGs from your Git repository by setting the Git repository URL and any required authentication credentials directly in Airflow's configuration files or through Helm chart values. This setup enables automated synchronization of DAGs, ensuring that Airflow is always up to date with the latest version of your workflows.

This integration enhances the development and deployment workflow by introducing full version control, enabling rollbacks, and supporting team collaboration in a production-grade setup.

## Make your Airflow on Kubernetes production-grade

The following best practices can help you make your **Apache Airflow on Kubernetes** deployment production-grade:

- Ensure you have a robust setup focused on scalability, security, and reliability.
- Use dedicated, autoscaling nodes, and select a resilient executor like **KubernetesExecutor**, **CeleryExecutor**, or **CeleryKubernetesExecutor**.
- Use a managed, high-availability database back end like MySQL or [PostgreSQL](deploy-postgresql-ha).
- Establish comprehensive monitoring and centralized logging to maintain performance insights.
- Secure your environment with network policies, SSL, and Role-Based Access Control (RBAC), and configure Airflow components (Scheduler, Web Server, Workers) for high availability.
- Implement CI/CD pipelines for smooth DAG deployment, and set up regular backups for disaster recovery.

---

# Create infrastructure for deploying a PostgreSQL database on AKS

In this article, you create the infrastructure resources needed to deploy a highly available PostgreSQL database on AKS using the [CloudNativePG (CNPG)](https://cloudnative-pg.io/) operator.

Important

Open-source software is mentioned throughout AKS documentation and samples. Software that you deploy is excluded from AKS service-level agreements, limited warranty, and Azure support. As you use open-source technology alongside AKS, consult the support options available from the respective communities and project maintainers to develop a plan.

Microsoft takes responsibility for building the open-source packages that we deploy on AKS. That responsibility includes having complete ownership of the build, scan, sign, validate, and hotfix process, along with control over the binaries in container images. For more information, see [Vulnerability management for AKS](concepts-vulnerability-management#aks-container-images) and [AKS support coverage](support-policies#aks-support-coverage).

## Before you begin

- Review the deployment overview and make sure you meet all the prerequisites in [How to deploy a highly available PostgreSQL database on AKS with Azure CLI](postgresql-ha-overview).
- Set environment variables for use throughout this guide.
- Install the required extensions.

## Set environment variables

Set the following environment variables for use throughout this guide:

```bash
export SUFFIX=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
export LOCAL_NAME="cnpg"
export TAGS="owner=user"
export RESOURCE_GROUP_NAME="rg-${LOCAL_NAME}-${SUFFIX}"
export PRIMARY_CLUSTER_REGION="canadacentral"
export AKS_PRIMARY_CLUSTER_NAME="aks-primary-${LOCAL_NAME}-${SUFFIX}"
export AKS_PRIMARY_MANAGED_RG_NAME="rg-${LOCAL_NAME}-primary-aksmanaged-${SUFFIX}"
export AKS_PRIMARY_CLUSTER_FED_CREDENTIAL_NAME="pg-primary-fedcred1-${LOCAL_NAME}-${SUFFIX}"
export AKS_PRIMARY_CLUSTER_PG_DNSPREFIX=$(echo $(echo "a$(openssl rand -hex 5 | cut -c1-11)"))
export AKS_UAMI_CLUSTER_IDENTITY_NAME="mi-aks-${LOCAL_NAME}-${SUFFIX}"
export AKS_CLUSTER_VERSION="1.32"
export PG_NAMESPACE="cnpg-database"
export PG_SYSTEM_NAMESPACE="cnpg-system"
export PG_PRIMARY_CLUSTER_NAME="pg-primary-${LOCAL_NAME}-${SUFFIX}"
export PG_PRIMARY_STORAGE_ACCOUNT_NAME="hacnpgpsa${SUFFIX}"
export PG_STORAGE_BACKUP_CONTAINER_NAME="backups"
export MY_PUBLIC_CLIENT_IP=$(dig +short myip.opendns.com @resolver3.opendns.com)
```

## Install required extensions

Install the extensions needed for Kubernetes integration and monitoring:

```bash
az extension add --upgrade --name k8s-extension --yes
az extension add --upgrade --name amg --yes
```

As a prerequisite for using `kubectl`, you need to first install [Krew](https://krew.sigs.k8s.io/), followed by the installation of the [CNPG plugin](https://cloudnative-pg.io/documentation/current/kubectl-plugin/#using-krew). These installations enable the management of the PostgreSQL operator using the subsequent commands.

```bash
(
    set -x; cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf "${KREW}.tar.gz" &&
    ./"${KREW}" install krew
)

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

kubectl krew install cnpg
```

## Create a resource group

Create a resource group to hold the resources you create in this guide using the [`az group create`](/en-us/cli/azure/group#az-group-create) command.

```bash
az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $PRIMARY_CLUSTER_REGION \
    --tags $TAGS \
    --query 'properties.provisioningState' \
    --output tsv
```

## Create a user-assigned managed identity

In this section, you create a user-assigned managed identity (UAMI) to allow the CNPG PostgreSQL to use an AKS workload identity to access Azure Blob Storage. This configuration allows the PostgreSQL cluster on AKS to connect to Azure Blob Storage without a secret.

1. Create a user-assigned managed identity using the [`az identity create`](/en-us/cli/azure/identity#az-identity-create) command.

    ```bash
    AKS_UAMI_WI_IDENTITY=$(az identity create \
        --name $AKS_UAMI_CLUSTER_IDENTITY_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $PRIMARY_CLUSTER_REGION \
        --output json)
    ```
2. Enable AKS workload identity and generate a service account to use later in this guide using the following commands:

    ```bash
    export AKS_UAMI_WORKLOAD_OBJECTID=$( \
        echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.principalId')
    export AKS_UAMI_WORKLOAD_RESOURCEID=$( \
        echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.id')
    export AKS_UAMI_WORKLOAD_CLIENTID=$( \
        echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.clientId')
    
    echo "ObjectId: $AKS_UAMI_WORKLOAD_OBJECTID"
    echo "ResourceId: $AKS_UAMI_WORKLOAD_RESOURCEID"
    echo "ClientId: $AKS_UAMI_WORKLOAD_CLIENTID"
    ```

The object ID is a unique identifier for the client ID (also known as the application ID) that uniquely identifies a security principal of type *Application* within the Microsoft Entra ID tenant. The resource ID is a unique identifier to manage and locate a resource in Azure. These values are required to enabled AKS workload identity.

The CNPG operator automatically generates a service account called *postgres* that you use later in the guide to create a federated credential that enables OAuth access from PostgreSQL to Azure Storage.

## Create a storage account in the primary region

1. Create an object storage account to store PostgreSQL backups in the primary region using the [`az storage account create`](/en-us/cli/azure/storage/account#az-storage-account-create) command.

    ```bash
    az storage account create \
        --name $PG_PRIMARY_STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $PRIMARY_CLUSTER_REGION \
        --sku Standard_ZRS \
        --kind StorageV2 \
        --query 'provisioningState' \
        --output tsv
    ```
2. Create the storage container to store the Write Ahead Logs (WAL) and regular PostgreSQL on-demand and scheduled backups using the [`az storage container create`](/en-us/cli/azure/storage/container#az-storage-container-create) command.

    ```bash
    az storage container create \
        --name $PG_STORAGE_BACKUP_CONTAINER_NAME \
        --account-name $PG_PRIMARY_STORAGE_ACCOUNT_NAME \
        --auth-mode login
    ```

    Example output:

    ```output
    {
        "created": true
    }
    ```

    Note

    If you encounter the error message: `The request may be blocked by network rules of storage account. Please check network rule set using 'az storage account show -n accountname --query networkRuleSet'. If you want to change the default action to apply when no rule matches, please use 'az storage account update'`. Make sure to verify user permissions for Azure Blob Storage and, if **necessary**, elevate your role to `Storage Blob Data Owner` using the commands provided and after retry the [`az storage container create`](/en-us/cli/azure/storage/container#az-storage-container-create) command.

    ```bash
    export USER_ID=$(az ad signed-in-user show --query id --output tsv)
    
    export STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID=$(az storage account show \
        --name $PG_PRIMARY_STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --query "id" \
        --output tsv)
    
    az role assignment list --scope $STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID --output table
    
    az role assignment create \
        --assignee-object-id $USER_ID \
        --assignee-principal-type User \
        --scope $STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID \
        --role "Storage Blob Data Owner" \
        --output tsv
    ```

## Assign RBAC to storage accounts

To enable backups, the PostgreSQL cluster needs to read and write to an object store. The PostgreSQL cluster running on AKS uses a workload identity to access the storage account via the CNPG operator configuration parameter [`inheritFromAzureAD`](https://cloudnative-pg.io/documentation/1.23/appendixes/object_stores/#azure-blob-storage).

1. Get the primary resource ID for the storage account using the [`az storage account show`](/en-us/cli/azure/storage/account#az-storage-account-show) command.

    ```bash
    export STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID=$(az storage account show \
        --name $PG_PRIMARY_STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --query "id" \
        --output tsv)
    
    echo $STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID
    ```
2. Assign the "Storage Blob Data Contributor" Azure built-in role to the object ID with the storage account resource ID scope for the UAMI associated with the managed identity for each AKS cluster using the [`az role assignment create`](/en-us/cli/azure/role/assignment#az-role-assignment-create) command.

    ```bash
    az role assignment create \
        --role "Storage Blob Data Contributor" \
        --assignee-object-id $AKS_UAMI_WORKLOAD_OBJECTID \
        --assignee-principal-type ServicePrincipal \
        --scope $STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID \
        --query "id" \
        --output tsv
    ```

## Set up monitoring infrastructure

In this section, you deploy an instance of Azure Managed Grafana, an Azure Monitor workspace, and an Azure Monitor Log Analytics workspace to enable monitoring of the PostgreSQL cluster. You also store references to the created monitoring infrastructure to use as input during the AKS cluster creation process later in the guide. This section might take some time to complete.

Note

Azure Managed Grafana instances and AKS clusters are billed independently. For more pricing information, see [Azure Managed Grafana pricing](https://azure.microsoft.com/pricing/details/managed-grafana/).

1. Create an Azure Managed Grafana instance using the [`az grafana create`](/en-us/cli/azure/grafana#az-grafana-create) command.

    ```bash
    export GRAFANA_PRIMARY="grafana-${LOCAL_NAME}-${SUFFIX}"
    
    export GRAFANA_RESOURCE_ID=$(az grafana create \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $GRAFANA_PRIMARY \
        --location $PRIMARY_CLUSTER_REGION \
        --zone-redundancy Enabled \
        --tags $TAGS \
        --query "id" \
        --output tsv)
    
    echo $GRAFANA_RESOURCE_ID
    ```
2. Create an Azure Monitor workspace using the [`az monitor account create`](/en-us/cli/azure/monitor/account#az-monitor-account-create) command.

    ```bash
    export AMW_PRIMARY="amw-${LOCAL_NAME}-${SUFFIX}"
    
    export AMW_RESOURCE_ID=$(az monitor account create \
        --name $AMW_PRIMARY \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $PRIMARY_CLUSTER_REGION \
        --tags $TAGS \
        --query "id" \
        --output tsv)
    
    echo $AMW_RESOURCE_ID
    ```
3. Create an Azure Monitor Log Analytics workspace using the [`az monitor log-analytics workspace create`](/en-us/cli/azure/monitor/log-analytics/workspace#az-monitor-log-analytics-workspace-create) command.

    ```bash
    export ALA_PRIMARY="ala-${LOCAL_NAME}-${SUFFIX}"
    
    export ALA_RESOURCE_ID=$(az monitor log-analytics workspace create \
        --resource-group $RESOURCE_GROUP_NAME \
        --workspace-name $ALA_PRIMARY \
        --location $PRIMARY_CLUSTER_REGION \
        --query "id" \
        --output tsv)
    
    echo $ALA_RESOURCE_ID
    ```

## Create the AKS cluster to host the PostgreSQL cluster

In this section, you create a multizone AKS cluster with a system node pool. The AKS cluster hosts the PostgreSQL cluster primary replica and two standby replicas, each aligned to a different availability zone to enable zone redundancy.

You also add a user node pool to the AKS cluster to host the PostgreSQL cluster. Using a separate node pool allows for control over the Azure VM SKUs used for PostgreSQL and enables the AKS system pool to optimize performance and costs. You apply a label to the user node pool that you can reference for node selection when deploying the CNPG operator later in this guide. This section might take some time to complete.

Important

If you opt to use local NVMe as your PostgreSQL storage in the later parts of this guide, you need to choose a VM SKU that supports local NVMe drives, for example, [Storage optimized VM SKUs](/en-us/azure/virtual-machines/sizes/overview#storage-optimized) or [GPU accelerated VM SKUs](/en-us/azure/virtual-machines/sizes/overview#gpu-accelerated). Update `$USER_NODE_POOL_VMSKU` accordingly.

1. Create an AKS cluster using the [`az aks create`](/en-us/cli/azure/aks#az-aks-create) command.

    ```bash
    export SYSTEM_NODE_POOL_VMSKU="standard_d2s_v3"
    export USER_NODE_POOL_NAME="postgres"
    export USER_NODE_POOL_VMSKU="standard_d4s_v3"
    
    az aks create \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --tags $TAGS \
        --resource-group $RESOURCE_GROUP_NAME \
        --location $PRIMARY_CLUSTER_REGION \
        --generate-ssh-keys \
        --node-resource-group $AKS_PRIMARY_MANAGED_RG_NAME \
        --enable-managed-identity \
        --assign-identity $AKS_UAMI_WORKLOAD_RESOURCEID \
        --network-plugin azure \
        --network-plugin-mode overlay \
        --network-dataplane cilium \
        --nodepool-name systempool \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --enable-cluster-autoscaler \
        --min-count 2 \
        --max-count 3 \
        --node-vm-size $SYSTEM_NODE_POOL_VMSKU \
        --enable-azure-monitor-metrics \
        --azure-monitor-workspace-resource-id $AMW_RESOURCE_ID \
        --grafana-resource-id $GRAFANA_RESOURCE_ID \
        --api-server-authorized-ip-ranges $MY_PUBLIC_CLIENT_IP \
        --tier standard \
        --kubernetes-version $AKS_CLUSTER_VERSION \
        --zones 1 2 3 \
        --output table
    ```
2. Wait for the initial cluster operation to complete using the [`az aks wait`](/en-us/cli/azure/aks#az-aks-wait) command so additional updates, such as adding the user node pool, don’t collide with an in-progress managed-cluster update:

    ```bash
    az aks wait \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --created
    ```
3. Add a user node pool to the AKS cluster using the [`az aks nodepool add`](/en-us/cli/azure/aks/nodepool#az-aks-nodepool-add) command.

    ```bash
    az aks nodepool add \
        --resource-group $RESOURCE_GROUP_NAME \
        --cluster-name $AKS_PRIMARY_CLUSTER_NAME \
        --name $USER_NODE_POOL_NAME \
        --enable-cluster-autoscaler \
        --min-count 3 \
        --max-count 6 \
        --node-vm-size $USER_NODE_POOL_VMSKU \
        --zones 1 2 3 \
        --labels workload=postgres \
        --output table
    ```

## Connect to the AKS cluster and create namespaces

In this section, you get the AKS cluster credentials, which serve as the keys that allow you to authenticate and interact with the cluster. Once connected, you create two namespaces: one for the CNPG controller manager services and one for the PostgreSQL cluster and its related services.

1. Get the AKS cluster credentials using the [`az aks get-credentials`](/en-us/cli/azure/aks#az-aks-get-credentials) command.

    ```bash
    az aks get-credentials \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --output none
    ```
2. Create the namespace for the CNPG controller manager services, the PostgreSQL cluster, and its related services by using the [`kubectl create namespace`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_namespace/) command.

    ```bash
    kubectl create namespace $PG_NAMESPACE --context $AKS_PRIMARY_CLUSTER_NAME
    kubectl create namespace $PG_SYSTEM_NAMESPACE --context $AKS_PRIMARY_CLUSTER_NAME
    ```

You can now define another environment variable based on your desired storage option, which you reference later in the guide when deploying PostgreSQL.

**Premium SSD**
You can reference the default preinstalled Premium SSD Azure Disks CSI driver storage class:

```bash
export POSTGRES_STORAGE_CLASS="managed-csi-premium"
```

**Premium SSD v2**
To use Premium SSD v2, you can create a custom storage class.

Define a new CSI driver storage class:

```bash
cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE -v 9 -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: premium2-disk-sc
parameters:
  cachingMode: None
  skuName: PremiumV2_LRS
  DiskIOPSReadWrite: "3500"
  DiskMBpsReadWrite: "125"
provisioner: disk.csi.azure.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

export POSTGRES_STORAGE_CLASS="premium2-disk-sc"
```

**Local NVMe**
Important

Ensure that your cluster is using VM SKUs that support local NVMe drives, for example, [Storage optimized VM SKUs](/en-us/azure/virtual-machines/sizes/overview#storage-optimized) or [GPU accelerated VM SKUs](/en-us/azure/virtual-machines/sizes/overview#gpu-accelerated). The below instructions require Azure Container Storage v2.0.0 or later.

1. Update AKS cluster to install Azure Container Storage on user node pool.

    ```bash
    az aks update \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --enable-azure-container-storage
    ```
2. Use the provided Azure Container Storage storage class.

    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: acstor-ephemeraldisk-nvme-db
    provisioner: localdisk.csi.acstor.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    EOF
    
    export POSTGRES_STORAGE_CLASS="acstor-ephemeraldisk-nvme-db"
    ```

## Update the monitoring infrastructure

The Azure Monitor workspace for Managed Prometheus and Azure Managed Grafana are automatically linked to the AKS cluster for metrics and visualization during the cluster creation process. In this section, you enable log collection with AKS Container insights and validate that Managed Prometheus is scraping metrics and Container insights is ingesting logs.

1. Enable Container insights monitoring on the AKS cluster using the [`az aks enable-addons`](/en-us/cli/azure/aks#az-aks-enable-addons) command.

    ```bash
    az aks enable-addons \
        --addon monitoring \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --workspace-resource-id $ALA_RESOURCE_ID \
        --output table
    ```
2. Validate that Managed Prometheus is scraping metrics and Container insights is ingesting logs from the AKS cluster by inspecting the DaemonSet using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command and the [`az aks show`](/en-us/cli/azure/aks#az-aks-show) command.

    ```bash
    kubectl get ds ama-metrics-node \
        --context $AKS_PRIMARY_CLUSTER_NAME \
        --namespace=kube-system
    
    kubectl get ds ama-logs \
        --context $AKS_PRIMARY_CLUSTER_NAME \
        --namespace=kube-system
    
    az aks show \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --query addonProfiles
    ```

    Your output should resemble the following example output, with *six* nodes total (three for the system node pool and three for the PostgreSQL node pool) and the Container insights showing `"enabled": true`:

    ```output
    NAME               DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
    ama-metrics-node   6         6         6       6            6           <none>       
    
    NAME               DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
    ama-logs           6         6         6       6            6           <none>       
    
    {
      "omsagent": {
        "config": {
          "logAnalyticsWorkspaceResourceID": "/subscriptions/aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e/resourceGroups/rg-cnpg-9vbin3p8/providers/Microsoft.OperationalInsights/workspaces/ala-cnpg-9vbin3p8",
          "useAADAuth": "true"
        },
        "enabled": true,
        "identity": null
      }
    }
    ```

## Create a public static IP for PostgreSQL cluster ingress

To validate deployment of the PostgreSQL cluster and use client PostgreSQL tooling, such as *psql* and *PgAdmin*, you need to expose the primary and read-only replicas to ingress. In this section, you create an Azure public IP resource that you later supply to an Azure load balancer to expose PostgreSQL endpoints for query.

1. Get the name of the AKS cluster node resource group using the [`az aks show`](/en-us/cli/azure/aks#az-aks-show) command.

    ```bash
    export AKS_PRIMARY_CLUSTER_NODERG_NAME=$(az aks show \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --query nodeResourceGroup \
        --output tsv)
    
    echo $AKS_PRIMARY_CLUSTER_NODERG_NAME
    ```
2. Create the public IP address using the [`az network public-ip create`](/en-us/cli/azure/network/public-ip#az-network-public-ip-create) command.

    ```bash
    export AKS_PRIMARY_CLUSTER_PUBLICIP_NAME="$AKS_PRIMARY_CLUSTER_NAME-pip"
    
    az network public-ip create \
        --resource-group $AKS_PRIMARY_CLUSTER_NODERG_NAME \
        --name $AKS_PRIMARY_CLUSTER_PUBLICIP_NAME \
        --location $PRIMARY_CLUSTER_REGION \
        --sku Standard \
        --zone 1 2 3 \
        --allocation-method static \
        --output table
    ```
3. Get the newly created public IP address using the [`az network public-ip show`](/en-us/cli/azure/network/public-ip#az-network-public-ip-show) command.

    ```bash
    export AKS_PRIMARY_CLUSTER_PUBLICIP_ADDRESS=$(az network public-ip show \
        --resource-group $AKS_PRIMARY_CLUSTER_NODERG_NAME \
        --name $AKS_PRIMARY_CLUSTER_PUBLICIP_NAME \
        --query ipAddress \
        --output tsv)
    
    echo $AKS_PRIMARY_CLUSTER_PUBLICIP_ADDRESS
    ```
4. Get the resource ID of the node resource group using the [`az group show`](/en-us/cli/azure/group#az-group-show) command.

    ```bash
    export AKS_PRIMARY_CLUSTER_NODERG_NAME_SCOPE=$(az group show --name \
        $AKS_PRIMARY_CLUSTER_NODERG_NAME \
        --query id \
        --output tsv)
    
    echo $AKS_PRIMARY_CLUSTER_NODERG_NAME_SCOPE
    ```
5. Assign the "Network Contributor" role to the UAMI object ID using the node resource group scope using the [`az role assignment create`](/en-us/cli/azure/role/assignment#az-role-assignment-create) command.

    ```bash
    az role assignment create \
        --assignee-object-id ${AKS_UAMI_WORKLOAD_OBJECTID} \
        --assignee-principal-type ServicePrincipal \
        --role "Network Contributor" \
        --scope ${AKS_PRIMARY_CLUSTER_NODERG_NAME_SCOPE}
    ```

## Install the CNPG operator in the AKS cluster

In this section, you install the CNPG operator in the AKS cluster using Helm or a YAML manifest.

**Helm**
1. Add the CNPG Helm repo using the [`helm repo add`](https://helm.sh/docs/helm/helm_repo_add/) command.

    ```bash
    helm repo add cnpg https://cloudnative-pg.github.io/charts
    ```
2. Upgrade the CNPG Helm repo and install it on the AKS cluster using the [`helm upgrade`](https://helm.sh/docs/helm/helm_upgrade/) command with the `--install` flag.

    ```bash
    helm upgrade --install cnpg \
        --namespace $PG_SYSTEM_NAMESPACE \
        --create-namespace \
        --kube-context=$AKS_PRIMARY_CLUSTER_NAME \
        cnpg/cloudnative-pg
    ```
3. Verify the operator installation on the AKS cluster using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command.

    ```bash
    kubectl get deployment \
        --context $AKS_PRIMARY_CLUSTER_NAME \
        --namespace $PG_SYSTEM_NAMESPACE cnpg-cloudnative-pg
    ```

**YAML**
1. Install the CNPG operator on the AKS cluster using the [`kubectl apply`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/) command.

    ```bash
    kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME \
        --namespace $PG_SYSTEM_NAMESPACE \
        --server-side -f \
        https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml
    ```
2. Verify the operator installation on the AKS cluster using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command.

    ```bash
    kubectl get deployment \
        --namespace $PG_SYSTEM_NAMESPACE cnpg-controller-manager \
        --context $AKS_PRIMARY_CLUSTER_NAME
    ```

---

# Deploy a highly available PostgreSQL database on AKS

In this article, you deploy a highly available PostgreSQL database on AKS.

- If you still need to create the required infrastructure for this deployment, follow the steps in [Create infrastructure for deploying a highly available PostgreSQL database on AKS](create-postgresql-ha) to get set up, and then return to this article.

Important

Open-source software is mentioned throughout AKS documentation and samples. Software that you deploy is excluded from AKS service-level agreements, limited warranty, and Azure support. As you use open-source technology alongside AKS, consult the support options available from the respective communities and project maintainers to develop a plan.

Microsoft takes responsibility for building the open-source packages that we deploy on AKS. That responsibility includes having complete ownership of the build, scan, sign, validate, and hotfix process, along with control over the binaries in container images. For more information, see [Vulnerability management for AKS](concepts-vulnerability-management#aks-container-images) and [AKS support coverage](support-policies#aks-support-coverage).

## Create secret for bootstrap app user

1. Generate a secret to validate the PostgreSQL deployment by interactive login for a bootstrap app user using the [`kubectl create secret`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret/) command.

Important

Microsoft recommends that you use the most secure authentication flow available. The authentication flow described in this procedure requires a high degree of trust in the application and carries risks that are not present in other flows. You should only use this flow when other more secure flows, such as managed identities, aren't viable.

```bash
PG_DATABASE_APPUSER_SECRET=$(echo -n | openssl rand -base64 16)

kubectl create secret generic db-user-pass \
    --from-literal=username=app \
     --from-literal=password="${PG_DATABASE_APPUSER_SECRET}" \
     --namespace $PG_NAMESPACE \
     --context $AKS_PRIMARY_CLUSTER_NAME
```

1. Validate that the secret was successfully created using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command.

    ```bash
    kubectl get secret db-user-pass --namespace $PG_NAMESPACE --context $AKS_PRIMARY_CLUSTER_NAME
    ```

## Set environment variables for the PostgreSQL cluster

- Deploy a ConfigMap to configure the CNPG operator using the following [`kubectl apply`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/) command. These values replace the legacy `ENABLE_AZURE_PVC_UPDATES` toggle, which is no longer required, and help stagger upgrades and speed up replica reconnections. Before rolling this configuration into production, validate that any existing `DRAIN_TAINTS` settings you rely on remain compatible with your Azure environment.

    ```bash
    cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE -f -
    apiVersion: v1
    kind: ConfigMap
    metadata:
        name: cnpg-controller-manager-config
    data:
        CLUSTERS_ROLLOUT_DELAY: '120'
        STANDBY_TCP_USER_TIMEOUT: '10'
    EOF
    ```

## Install the Prometheus PodMonitors

Prometheus scrapes CNPG using the recording rules stored in the CNPG GitHub samples repo. Because the operator-managed PodMonitor is being deprecated, create and manage the PodMonitor resource yourself so you can tailor it to your monitoring stack.

1. Add the Prometheus Community Helm repo using the [`helm repo add`](https://helm.sh/docs/helm/helm_repo_add/) command.

    ```bash
    helm repo add prometheus-community \
        https://prometheus-community.github.io/helm-charts
    ```
2. Upgrade the Prometheus Community Helm repo and install it on the primary cluster using the [`helm upgrade`](https://helm.sh/docs/helm/helm_upgrade/) command with the `--install` flag.

    ```bash
    helm upgrade --install \
        --namespace $PG_NAMESPACE \
        -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/kube-stack-config.yaml \
        prometheus-community \
        prometheus-community/kube-prometheus-stack \
        --kube-context=$AKS_PRIMARY_CLUSTER_NAME
    ```
3. Create a PodMonitor for the cluster. The CNPG team is deprecating the operator-managed PodMonitor, so you now manage it directly:

    ```bash
    cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME --namespace $PG_NAMESPACE -f -
    apiVersion: monitoring.coreos.com/v1
    kind: PodMonitor
    metadata:
      name: $PG_PRIMARY_CLUSTER_NAME
      namespace: ${PG_NAMESPACE}
      labels:
        cnpg.io/cluster: ${PG_PRIMARY_CLUSTER_NAME}
    spec:
      selector:
        matchLabels:
          cnpg.io/cluster: ${PG_PRIMARY_CLUSTER_NAME}
      podMetricsEndpoints:
        - port: metrics
    EOF
    ```

## Create a federated credential

In this section, you create a federated identity credential for PostgreSQL backup to allow CNPG to use AKS workload identity to authenticate to the storage account destination for backups. The CNPG operator creates a Kubernetes service account with the same name as the cluster named used in the CNPG Cluster deployment manifest.

1. Get the OIDC issuer URL of the cluster using the [`az aks show`](/en-us/cli/azure/aks#az-aks-show) command.

    ```bash
    export AKS_PRIMARY_CLUSTER_OIDC_ISSUER="$(az aks show \
        --name $AKS_PRIMARY_CLUSTER_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)"
    ```
2. Create a federated identity credential using the [`az identity federated-credential create`](/en-us/cli/azure/identity/federated-credential#az-identity-federated-credential-create) command.

    ```bash
    az identity federated-credential create \
        --name $AKS_PRIMARY_CLUSTER_FED_CREDENTIAL_NAME \
        --identity-name $AKS_UAMI_CLUSTER_IDENTITY_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --issuer "${AKS_PRIMARY_CLUSTER_OIDC_ISSUER}" \
        --subject system:serviceaccount:"${PG_NAMESPACE}":"${PG_PRIMARY_CLUSTER_NAME}" \
        --audience api://AzureADTokenExchange
    ```

## Deploy a highly available PostgreSQL cluster

In this section, you deploy a highly available PostgreSQL cluster using the [CNPG Cluster custom resource definition (CRD)](https://cloudnative-pg.io/documentation/1.23/cloudnative-pg.v1/#postgresql-cnpg-io-v1-ClusterSpec).

### Cluster CRD parameters

The following table outlines the key properties set in the YAML deployment manifest for the Cluster CRD:

| Property | Definition |
| --- | --- |
| `imageName` | Points to the CloudNativePG operand container image. Use `ghcr.io/cloudnative-pg/postgresql:18-system-trixie` with the in-core backup integration shown in this guide, or switch to `18-standard-trixie` when you adopt the Barman Cloud plugin. |
| `inheritedMetadata` | Specific to the CNPG operator. The CNPG operator applies the metadata to every object related to the cluster. |
| `annotations` | Includes the DNS label required when exposing the cluster endpoints and enables [`alpha.cnpg.io/failoverQuorum`](https://cloudnative-pg.io/documentation/current/failover/#failover-quorum-quorum-based-failover) for quorum-based failover. |
| `labels: azure.workload.identity/use: "true"` | Indicates that AKS should inject workload identity dependencies into the pods hosting the PostgreSQL cluster instances. |
| `topologySpreadConstraints` | Require different zones and different nodes with label `"workload=postgres"`. |
| `resources` | Configures a Quality of Service (QoS) class of *Guaranteed*. In a production environment, these values are key for maximizing usage of the underlying node VM and vary based on the Azure VM SKU used. |
| `probes` | Replaces the legacy `startDelay` configuration. Streaming startup and readiness probes help ensure replicas are healthy before serving traffic. |
| `smartShutdownTimeout` | Allows long-running transactions to finish gracefully during updates instead of using aggressive stop delays. |
| `bootstrap` | Specific to the CNPG operator. Initializes with an empty app database. |
| `storage` | Defines the PersistentVolume settings for the database. With Azure Managed Disks, the simplified syntax keeps data and WAL on the same 64-GiB volume, which offers better throughput tiers on managed disks. Adjust if you need separate WAL volumes. |
| `postgresql.synchronous` | Replaces `minSyncReplicas`/`maxSyncReplicas` and lets you specify synchronous replication behavior using the newer schema. |
| `postgresql.parameters` | Specific to the CNPG operator. Maps settings for `postgresql.conf`, `pg_hba.conf`, and `pg_ident.conf`. The sample emphasizes observability and WAL retention defaults that suit the AKS workload identity scenario but should be tuned per workload. |
| `serviceAccountTemplate` | Contains the template needed to generate the service accounts and maps the AKS federated identity credential to the UAMI to enable AKS workload identity authentication from the pods hosting the PostgreSQL instances to external Azure resources. |
| `barmanObjectStore` | Specific to the CNPG operator. Configures the barman-cloud tool suite using AKS workload identity for authentication to the Azure Blob Storage object store. |

To further isolate PostgreSQL workloads, you can add a taint (for example, `node-role.kubernetes.io/postgres=:NoSchedule`) to your data plane nodes and replace the sample `nodeSelector`/`tolerations` with the values recommended by CloudNativePG. If you take this approach, label the nodes accordingly and confirm the AKS autoscaler policies align with your topology.

### PostgreSQL performance parameters

PostgreSQL performance heavily depends on your cluster's underlying resources and workload. The following table provides baseline guidance for a three-node cluster running on Standard D4s v3 nodes (16-GiB memory). Treat these values as a starting point and adjust them once you understand your workload profile:

| Property | Recommended value | Definition |
| --- | --- | --- |
| `wal_compression` | lz4 | Compresses full-page writes written in WAL file with specified method |
| `max_wal_size` | 6 GB | Sets the WAL size that triggers a checkpoint |
| `checkpoint_timeout` | 15 min | Sets the maximum time between automatic WAL checkpoints |
| `checkpoint_completion_target` | 0.9 | Balances checkpoint work across the checkpoint window |
| `checkpoint_flush_after` | 2 MB | Number of pages after which previously performed writes are flushed to disk |
| `wal_writer_flush_after` | 2 MB | Amount of WAL written out by WAL writer that triggers a flush |
| `min_wal_size` | 2 GB | Sets the minimum size to shrink the WAL to |
| `max_slot_wal_keep_size` | 10 GB | Upper bound for WAL left to service replication slots |
| `shared_buffers` | 4 GB | Sets the number of shared memory buffers used by the server (25% of node memory in this example) |
| `effective_cache_size` | 12 GB | Sets the planner's assumption about the total size of the data caches |
| `work_mem` | 1/256th of node memory | Sets the maximum memory to be used for query workspaces |
| `maintenance_work_mem` | 6.25% of node memory | Sets the maximum memory to be used for maintenance operations |
| `autovacuum_vacuum_cost_limit` | 2400 | Vacuum cost amount available before napping, for autovacuum |
| `random_page_cost` | 1.1 | Sets the planner's estimate of the cost of a nonsequentially fetched disk page |
| `effective_io_concurrency` | 64 | Sets how many simultaneous requests the disk subsystem can handle efficiently |
| `maintenance_io_concurrency` | 64 | A variant of "effective\_io\_concurrency" that is used for maintenance work |

### Deploying PostgreSQL

**Azure Disk (Premium SSD/Premium SSD v2)**
1. Deploy the PostgreSQL cluster with the Cluster CRD using the [`kubectl apply`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/) command.

    ```bash
    cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE -v 9 -f -
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: $PG_PRIMARY_CLUSTER_NAME
      annotations:
        alpha.cnpg.io/failoverQuorum: "true"
    spec:
      imageName: ghcr.io/cloudnative-pg/postgresql:18-system-trixie
      inheritedMetadata:
        annotations:
          service.beta.kubernetes.io/azure-dns-label-name: $AKS_PRIMARY_CLUSTER_PG_DNSPREFIX
        labels:
          azure.workload.identity/use: "true"
    
      instances: 3
      smartShutdownTimeout: 30
    
      probes:
        startup:
          type: streaming
          maximumLag: 32Mi
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 120
        readiness:
          type: streaming
          maximumLag: 0
          periodSeconds: 10
          failureThreshold: 6
    
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            cnpg.io/cluster: $PG_PRIMARY_CLUSTER_NAME
    
      affinity:
        nodeSelector:
          workload: postgres
    
      resources:
        requests:
          memory: '8Gi'
          cpu: 2
        limits:
          memory: '8Gi'
          cpu: 2
    
      bootstrap:
        initdb:
          database: appdb
          owner: app
          secret:
            name: db-user-pass
          dataChecksums: true
    
      storage:
        storageClass: $POSTGRES_STORAGE_CLASS
        size: 64Gi
    
      postgresql:
        synchronous:
          method: any
          number: 1
        parameters:
          wal_compression: lz4
          max_wal_size: 6GB
          max_slot_wal_keep_size: 10GB
          checkpoint_timeout: 15min
          checkpoint_completion_target: '0.9'
          checkpoint_flush_after: 2MB
          wal_writer_flush_after: 2MB
          min_wal_size: 2GB
          shared_buffers: 4GB
          effective_cache_size: 12GB
          work_mem: 62MB
          maintenance_work_mem: 1GB
          autovacuum_vacuum_cost_limit: "2400"
          random_page_cost: "1.1"
          effective_io_concurrency: "64"
          maintenance_io_concurrency: "64"
          log_checkpoints: 'on'
          log_lock_waits: 'on'
          log_min_duration_statement: '1000'
          log_statement: 'ddl'
          log_temp_files: '1024'
          log_autovacuum_min_duration: '1s'
          pg_stat_statements.max: '10000'
          pg_stat_statements.track: 'all'
          hot_standby_feedback: 'on'
        pg_hba:
          - host all all all scram-sha-256
    
      serviceAccountTemplate:
        metadata:
          annotations:
            azure.workload.identity/client-id: "$AKS_UAMI_WORKLOAD_CLIENTID"
          labels:
            azure.workload.identity/use: "true"
    
      backup:
        barmanObjectStore:
          destinationPath: "https://${PG_PRIMARY_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/backups"
          azureCredentials:
            inheritFromAzureAD: true
        retentionPolicy: '7d'
    EOF
    ```

Note

The sample manifest uses the `ghcr.io/cloudnative-pg/postgresql:18-system-trixie` image because it works with the in-core Barman Cloud integration shown later. When you're ready to switch to the Barman Cloud plugin, update `spec.imageName` to `ghcr.io/cloudnative-pg/postgresql:18-standard-trixie` and follow the [plugin configuration guidance](https://cloudnative-pg.io/plugin-barman-cloud/docs/intro/) before redeploying the cluster.

Important

The example `pg_hba` entry allows non-TLS access. If you keep this configuration, document the security implications for your team and prefer encrypted connections wherever possible.

**Azure Container Storage (local NVMe)**
1. Deploy the PostgreSQL cluster with the Cluster CRD using the [`kubectl apply`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/) command.

    ```bash
    cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE -v 9 -f -
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: $PG_PRIMARY_CLUSTER_NAME
      annotations:
        alpha.cnpg.io/failoverQuorum: "true"
    spec:
      imageName: ghcr.io/cloudnative-pg/postgresql:18-system-trixie
      inheritedMetadata:
        annotations:
          service.beta.kubernetes.io/azure-dns-label-name: $AKS_PRIMARY_CLUSTER_PG_DNSPREFIX
          localdisk.csi.acstor.io/accept-ephemeral-storage: "true"
        labels:
          azure.workload.identity/use: "true"
    
      instances: 3
      smartShutdownTimeout: 30
    
      probes:
        startup:
          type: streaming
          maximumLag: 32Mi
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 120
        readiness:
          type: streaming
          maximumLag: 0
          periodSeconds: 10
          failureThreshold: 6
    
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            cnpg.io/cluster: $PG_PRIMARY_CLUSTER_NAME
    
      affinity:
        nodeSelector:
          workload: postgres
    
      resources:
        requests:
          memory: '8Gi'
          cpu: 2
        limits:
          memory: '8Gi'
          cpu: 2
    
      bootstrap:
        initdb:
          database: appdb
          owner: app
          secret:
            name: db-user-pass
          dataChecksums: true
    
      storage:
        size: 32Gi
        pvcTemplate:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 32Gi
          storageClassName: $POSTGRES_STORAGE_CLASS
    
      postgresql:
        synchronous:
          method: any
          number: 1
        parameters:
          wal_compression: lz4
          max_wal_size: 6GB
          max_slot_wal_keep_size: 10GB
          checkpoint_timeout: 15min
          checkpoint_completion_target: '0.9'
          checkpoint_flush_after: 2MB
          wal_writer_flush_after: 2MB
          min_wal_size: 2GB
          shared_buffers: 4GB
          effective_cache_size: 12GB
          work_mem: 62MB
          maintenance_work_mem: 1GB
          autovacuum_vacuum_cost_limit: "2400"
          random_page_cost: "1.1"
          effective_io_concurrency: "64"
          maintenance_io_concurrency: "64"
          log_checkpoints: 'on'
          log_lock_waits: 'on'
          log_min_duration_statement: '1000'
          log_statement: 'ddl'
          log_temp_files: '1024'
          log_autovacuum_min_duration: '1s'
          pg_stat_statements.max: '10000'
          pg_stat_statements.track: 'all'
          hot_standby_feedback: 'on'
        pg_hba:
          - host all all all scram-sha-256
    
      serviceAccountTemplate:
        metadata:
          annotations:
            azure.workload.identity/client-id: "$AKS_UAMI_WORKLOAD_CLIENTID"
          labels:
            azure.workload.identity/use: "true"
    
      backup:
        barmanObjectStore:
          destinationPath: "https://${PG_PRIMARY_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/backups"
          azureCredentials:
            inheritFromAzureAD: true
        retentionPolicy: '7d'
    EOF
    ```

1. Validate that the primary PostgreSQL cluster was successfully created using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command. The CNPG Cluster CRD specified three instances, which can be validated by viewing running pods once each instance is brought up and joined for replication. Be patient as it can take some time for all three instances to come online and join the cluster.

    ```bash
    kubectl get pods --context $AKS_PRIMARY_CLUSTER_NAME --namespace $PG_NAMESPACE -l cnpg.io/cluster=$PG_PRIMARY_CLUSTER_NAME
    ```

    Example output

    ```output
    NAME                         READY   STATUS    RESTARTS   AGE
    pg-primary-cnpg-r8c7unrw-1   1/1     Running   0          4m25s
    pg-primary-cnpg-r8c7unrw-2   1/1     Running   0          3m33s
    pg-primary-cnpg-r8c7unrw-3   1/1     Running   0          2m49s
    ```

Important

If you use local NVMe with Azure Container Storage and a pod remains in the init state with a multi-attach error, the pod is still searching for the volume on a lost node. After the pod starts running, it enters a `CrashLoopBackOff` state because CNPG creates a new replica on a new node without data and can't find the `pgdata` directory. To resolve this issue, destroy the affected instance and bring up a new one. Run the following command:

```bash
kubectl cnpg destroy [cnpg-cluster-name] [instance-number]  
```

## Validate the Prometheus PodMonitor is running

The manually created PodMonitor ties the kube-prometheus-stack scrape configuration to the CNPG pods you deployed earlier.

Validate the PodMonitor is running using the [`kubectl get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/) command.

```bash
kubectl --namespace $PG_NAMESPACE \
    --context $AKS_PRIMARY_CLUSTER_NAME \
    get podmonitors.monitoring.coreos.com \
    $PG_PRIMARY_CLUSTER_NAME \
    --output yaml
```

Example output

```output
kind: PodMonitor
metadata:
  labels:
    cnpg.io/cluster: pg-primary-cnpg-r8c7unrw
  name: pg-primary-cnpg-r8c7unrw
  namespace: cnpg-database
spec:
  podMetricsEndpoints:
  - port: metrics
  selector:
    matchLabels:
      cnpg.io/cluster: pg-primary-cnpg-r8c7unrw
```

If you're using Azure Monitor for Managed Prometheus, you need to add another pod monitor using the custom group name. Managed Prometheus doesn't pick up the custom resource definitions (CRDs) from the Prometheus community. Aside from the group name, the CRDs are the same. That design lets pod monitors for Managed Prometheus run alongside pod monitors that use the community CRD. If you're not using Managed Prometheus, you can skip this section. Create a new pod monitor:

```bash
cat <<EOF | kubectl apply --context $AKS_PRIMARY_CLUSTER_NAME --namespace $PG_NAMESPACE -f -
apiVersion: azmonitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cnpg-cluster-metrics-managed-prometheus
  namespace: ${PG_NAMESPACE}
  labels:
    azure.workload.identity/use: "true"
    cnpg.io/cluster: ${PG_PRIMARY_CLUSTER_NAME}
spec:
  selector:
    matchLabels:
      azure.workload.identity/use: "true"
      cnpg.io/cluster: ${PG_PRIMARY_CLUSTER_NAME}
  podMetricsEndpoints:
    - port: metrics
EOF
```

Verify that the pod monitor is created (note the difference in the group name).

```bash
kubectl --namespace $PG_NAMESPACE \
    --context $AKS_PRIMARY_CLUSTER_NAME \
    get podmonitors.azmonitoring.coreos.com \
    -l cnpg.io/cluster=$PG_PRIMARY_CLUSTER_NAME \
    -o yaml
```

### Option A - Azure Monitor workspace

After you deploy the Postgres cluster and the pod monitor, you can view the metrics using the Azure portal in an Azure Monitor workspace.

![Screenshot showing Postgres cluster metrics in an Azure Monitor workspace in the Azure portal.](media/prometheus-metrics.png)

### Option B - Managed Grafana

Alternatively, after you deploy the Postgres cluster and pod monitors, you can create a metrics dashboard on the Managed Grafana instance created by the deployment script to visualize the metrics exported to the Azure Monitor workspace. You can access the Managed Grafana via the Azure portal. Navigate to the Managed Grafana instance created by the deployment script and select the Endpoint link as shown here:

![Screenshot Postgres cluster metrics in an Azure Managed Grafana instance in the Azure portal.](media/grafana-metrics-1.png)

Selecting the Endpoint link opens a new browser window where you can create dashboards on the Managed Grafana instance. Following the instructions to [configure an Azure Monitor data source](/en-us/azure/azure-monitor/visualize/grafana-plugin#configure-an-azure-monitor-data-source-plug-in), you can then add visualizations to create a dashboard of metrics from the Postgres cluster. After setting up the data source connection, from the main menu, select the Data sources option. You should see a set of data source options for the data source connection as shown here:

![Screenshot showing Azure Monitor data source options in the Azure portal.](media/grafana-metrics-2.png)

On the Managed Prometheus option, select the option to build a dashboard to open the dashboard editor. After the editor window opens, select the Add visualization option then select the Managed Prometheus option to browse the metrics from the Postgres cluster. After you select the metric you want to visualize, select the Run queries button to fetch the data for the visualization as shown here:

![Screenshot showing a Managed Prometheus dashboard with Postgres cluster metrics.](media/grafana-metrics-3.png)

Select the Save icon to add the panel to your dashboard. You can add other panels by selecting the Add button in the dashboard editor and repeating this process to visualize other metrics. Adding the metrics visualizations, you should have something that looks like this:

![Screenshot showing a saved Managed Prometheus dashboard in the Azure portal.](media/grafana-metrics-4.png)

Select the Save icon to save your dashboard.

---

# Cloud Native

- https://kubearmor.io/
  - https://github.com/kubearmor
  - https://github.com/kubearmor/kubearmor-relay-server-KA

- https://github.com/inspektor-gadget
  
- https://github.com/topics/cncf-project?o=desc&s=forks