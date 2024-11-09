# Azure Kubernetes Service (AKS) Networking Guide

This guide explores different networking configurations in AKS using various Container Network Interface (CNI) options. Each configuration is tested and documented with specific characteristics and limitations. Also it experiments with Calico Cloud Security Solution. <https://calicocloud.io>

## Table of Contents
- [Azure Kubernetes Service (AKS) Networking Guide](#azure-kubernetes-service-aks-networking-guide)
  - [Table of Contents](#table-of-contents)
  - [Network Configuration Parameters](#network-configuration-parameters)
  - [CNI Options](#cni-options)
    - [kubelet CNI](#kubelet-cni)
    - [Azure CNI](#azure-cni)
    - [Azure CNI - Overlay](#azure-cni---overlay)
    - [Azure CNI - Calico](#azure-cni---calico)
    - [Azure CNI - Cilium](#azure-cni---cilium)
    - [Azure CNI - Cilium - Overlay](#azure-cni---cilium---overlay)
  - [BYOCNI - Calico - Overlay](#byocni---calico---overlay)
    - [BYOCNI - Calico](#byocni---calico)
  - [Testing](#testing)
  - [Clean up](#clean-up)
  - [Contributing](#contributing)


## Network Configuration Parameters

| Parameter | Allowed Values | Description |
|-----------|---------------|-------------|
| `--network-dataplane` | `azure`, `cilium` | Controls the network dataplane. Use `azure` for default or `cilium` for Cilium dataplane. |
| `--network-plugin` | `azure`, `kubenet`, `none` | Determines the CNI plugin. `azure` for VNET-routable IPs, `kubenet` for overlay network, `none` for BYO CNI. |
| `--network-plugin-mode` | `overlay` | Controls CNI mode. `overlay` with Azure CNI uses non-VNET IPs for pods. |
| `--network-policy` | `azure`, `calico`, `cilium`, `""` | (PREVIEW) Enables network policies. Works with Azure CNI. Default is disabled (`""`). |


## CNI Options

Before starting creating the AKS clusters, let's create a Azure Resource Group to accomodate all of them.

1. Define the variables.

   ```bash
   RG='aks-flavours'
   LOCATION='westus2'
   K8S_VERSION=1.30
   ```

2. Create the Resource Group in the desired Region.

   ```bash
   az group create \
     --name $RG \
     --location $LOCATION
   ```

### kubelet CNI

Kubenet is a basic network plugin that provides simple and lightweight networking for Kubernetes clusters.

**Key Characteristics:**

- ❌ Network policies not supported
- ❌ Not supported by Calico Cloud
- 🔍 Uses bridge CNI plugin
- 📡 NAT-based networking
- 🌐 Pod IPs are not directly routable outside the cluster

**Use Cases:**

- Development and testing environments
- Small-scale clusters
- Scenarios where pod-to-pod communication across nodes is limited
- Budget-conscious deployments (uses less IP addresses)

**Configuration:**

```bash
CLUSTER_NAME='azcni-kubenet'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin kubenet \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

> [!WARNING] Network policies do not work.

Not supported by Calico Cloud.

```console
Fri Aug 16 2024 14:37:58 GMT-0600 (Mountain Daylight Time)
2024-08-16T20:37:58+00:00 [info] cluster_migratable:begin - Checking if cluster can be migrated
2024-08-16T20:38:34+00:00 [info] queryForInstalledCNI:begin - Checking for installed CNI Plugin
2024-08-16T20:38:41+00:00 [error] Detected plugin bridge, it is currently not supported
```

**CNI Configuration Details:**

```json
{
   "cniVersion":"0.3.0",
   "name":"azure",
   "plugins":[
      {
         "type":"bridge",
         "bridge":"cbr0",
         "mtu": 1500,
         "addIf":"eth0",
         "isGateway":true,
         "ipMasq":true,
         "hairpinMode":false,
         "ipam":{
            "type":"host-local",
            "ranges":[[{"subnet":"10.244.0.0/24"}]]
         }
      }
   ]
}
```

**Limitations:**

- Limited to 400 nodes
- No support for Windows node pools
- Network policies not available
- Pod IPs are not routable outside the cluster
- Higher latency due to NAT

### Azure CNI

Azure CNI provides advanced networking capabilities with full integration into Azure Virtual Networks.

**Key Characteristics:**

- ✅ Network policies work after Calico Cloud connection
- 🔄 Traffic uses pod IP as source
- ✅ Direct pod IP accessibility from outside
- 🔍 Uses azure-vnet CNI plugin
- 🌐 Pod IPs are routable within VNET

**Use Cases:**

- Production environments
- Enterprise deployments
- Scenarios requiring direct pod connectivity
- Integration with other Azure services
- Multi-tenant clusters

**Configuration:**

```bash
CLUSTER_NAME='azcni-azure'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin azure \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
WARNING: The behavior of this command has been altered by the following extension: aks-preview
  "networkProfile": {
    "networkDataplane": "azure",
    "networkMode": null,
    "networkPlugin": "azure",
    "networkPluginMode": null,
    "networkPolicy": "none",
```

```console
2024-08-16T21:15:30+00:00 [info] cluster_migratable:begin - Checking if cluster can be migrated
2024-08-16T21:16:07+00:00 [info] queryForInstalledCNI:begin - Checking for installed CNI Plugin
2024-08-16T21:16:09+00:00 [info] installer - Creating Tigera Pull Secret
2024-08-16T21:16:17+00:00 [info] queryForInstalledCNI:end - Found CNI Plugin azure-vnet
2024-08-16T21:16:17+00:00 [info] cluster_migratable:end - Cluster can be migrated
```

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

```json
{
   "cniVersion":"0.3.0",
   "name":"azure",
   "plugins":[
      {
         "type":"azure-vnet",
         "mode":"transparent",
         "ipsToRouteViaHost":["169.254.20.10"],
         "ipam":{
            "type":"azure-vnet-ipam"
         }
      },
      {
         "type":"portmap",
         "capabilities":{
            "portMappings":true
         },
         "snat":true
      }
   ]
}
```

**Features:**

- Direct pod connectivity
- Network policy support
- Windows node pool support
- Integration with Azure Load Balancer
- Support for multiple node pools
- Private cluster support

**Limitations:**

- Requires more IP addresses
- Higher planning overhead for IP address management
- Network policies require additional configuration


> [!WARNING]
> - Network policies do not work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.

### Azure CNI - Overlay

Azure CNI Overlay mode provides a balance between the simplicity of Kubenet and the advanced features of Azure CNI.

**Key Characteristics:**

- ✅ Network policies work after Calico Cloud connection
- 🔄 Traffic uses node IP as source
- ❌ Pod IPs not directly accessible
- 🔍 Uses azure-vnet CNI with overlay mode
- 🌐 Efficient IP address usage

**Use Cases:**

- Large-scale clusters
- Scenarios with limited IP address space
- Multi-tenant environments
- Development and staging environments
- Hybrid connectivity scenarios

**Configuration:**

```bash
CLUSTER_NAME='azcni-azure-overlay'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
  "networkProfile": {
    "networkDataplane": "azure",
    "networkMode": null,
    "networkPlugin": "azure",
    "networkPluginMode": "overlay",
    "networkPolicy": "none",
</pre>

```console
2024-08-16T21:33:11+00:00 [info] cluster_migratable:begin - Checking if cluster can be migrated
2024-08-16T21:33:47+00:00 [info] queryForInstalledCNI:begin - Checking for installed CNI Plugin
2024-08-16T21:33:48+00:00 [info] installer - Creating Tigera Pull Secret
2024-08-16T21:33:55+00:00 [info] queryForInstalledCNI:end - Found CNI Plugin azure-vnet
2024-08-16T21:33:55+00:00 [info] cluster_migratable:end - Cluster can be migrated
```

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

**CNI Configuration Details:**

```json
{
	"cniVersion": "0.3.0",
	"name": "azure",
	"plugins": [
		{
			"type": "azure-vnet",
			"mode": "transparent",
			"ipsToRouteViaHost": [
				"169.254.20.10"
			],
			"executionMode": "v4swift",
			"ipam": {
				"mode": "v4overlay",
				"type": "azure-cns"
			},
			"dns": {},
			"runtimeConfig": {
				"dns": {}
			},
			"windowsSettings": {}
		},
		{
			"type": "portmap",
			"capabilities": {
				"portMappings": true
			},
			"snat": true
		}
	]
}
```

**Features:**
- Efficient IP address utilization
- Simplified network planning
- Network policy support
- Windows node pool support
- Support for multiple node pools

**Limitations:**
- Pod IPs not directly accessible from outside cluster
- Additional overlay network overhead
- SNAT required for external communication

> [!WARNING]
> - Network policies do not work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with the node ip address as source ip.
> - Traffic is not routeable to the pod using its IP address.

### Azure CNI - Calico

Azure CNI with Calico provides advanced networking with robust network policy capabilities.

**Key Characteristics:**

- ✅ Network policies work by default
- ✅ Calico Cloud integration supported
- 🔄 Traffic uses pod IP as source
- ✅ Direct pod IP accessibility
- 🔍 Uses azure-vnet CNI with Calico policy enforcement

**Use Cases:**

- Security-focused deployments
- Multi-tenant clusters
- Environments requiring micro-segmentation
- Compliance-driven deployments
- Zero-trust network architectures

**Configuration:**

```bash
CLUSTER_NAME='azcni-azure-calico'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin azure \
  --network-policy calico \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
      "networkProfile": {
  "networkProfile": {
    "networkDataplane": "azure",
    "networkMode": null,
    "networkPlugin": "azure",
    "networkPluginMode": null,
    "networkPolicy": "calico",
</pre>

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

**CNI Configuration Details:**

```json
{
   "cniVersion":"0.3.0",
   "name":"azure",
   "plugins":[
      {
         "type":"azure-vnet",
         "mode":"transparent",
         "ipsToRouteViaHost":["169.254.20.10"],
         "ipam":{
            "type":"azure-vnet-ipam"
         }
      },
      {
         "type":"portmap",
         "capabilities":{
            "portMappings":true
         },
         "snat":true
      }
   ]
}
```

**Features:**

- Advanced network policy capabilities
- Fine-grained access controls
- Network flow logs
- Integration with external security tools
- Support for egress gateway
- Host endpoint protection

**Limitations:**

- Higher resource overhead
- More complex configuration
- Requires understanding of Calico policies

> [!WARNING]
> - Network policies work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.


### Azure CNI - Cilium

Azure CNI with Cilium provides eBPF-based networking with advanced security and observability features.

**Key Characteristics:**
- ✅ Network policies work by default
- ✅ Advanced eBPF features
- 🔄 Traffic uses pod IP as source
- ✅ Direct pod IP accessibility
- 🔍 Uses Cilium CNI with Azure IPAM

**Use Cases:**
- High-performance environments
- Security-critical deployments
- Service mesh implementations
- Environments requiring deep observability
- Large-scale clusters

**Configuration:**

Create a Vnet with 2 subnets - 1 for hosts, another for pods.
Create the cluster, referencing the node subnet using `--vnet-subnet-id` and the pod subnet using `--pod-subnet-id` and enabling cilium dataplane w/o overlay.

```bash
CLUSTER_NAME='azcni-azure-cilium'
POD_CIDR='192.168.0.0/16'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-dataplane cilium \
  --network-plugin azure \
  --network-policy cilium \
  --vnet-subnet-id /subscriptions/03cfb895-358d-4ad4-8aba-aeede8dbfc30/resourceGroups/rmartins/providers/Microsoft.Network/virtualNetworks/cilium-pod-subnet/subnets/default \
  --pod-subnet-id /subscriptions/03cfb895-358d-4ad4-8aba-aeede8dbfc30/resourceGroups/rmartins/providers/Microsoft.Network/virtualNetworks/cilium-pod-subnet/subnets/pod-subnet \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
      "networkProfile": {
  "networkProfile": {
    "networkDataplane": "cilium",
    "networkMode": null,
    "networkPlugin": "azure",
    "networkPluginMode": null,
    "networkPolicy": "cilium",
</pre>

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

**CNI Configuration Details:**

```json
{
	"cniVersion": "0.3.1",
	"name": "cilium",
	"plugins": [
		{
			"type": "cilium-cni",
			"ipam": {
				"type": "azure-ipam"
			},
			"enable-debug": true,
			"log-file": "/var/log/cilium-cni.log"
		}
	]
}
```

**Features:**

- eBPF-based networking
- Advanced observability
- Layer 7 policy enforcement
- Transparent encryption
- Service mesh capabilities
- Advanced load balancing

**Limitations:**

- Higher system requirements
- More complex troubleshooting
- Limited Windows support

While connecting to Calico Cloud

```console
2024-08-20T14:49:56+00:00 [error] Detected plugin cilium-cni, it is currently not supported
```

> [!WARNING]
> - Network policies work by default.


> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.

### Azure CNI - Cilium - Overlay

```bash
CLUSTER_NAME='azcni-azure-cilium-overlay'
POD_CIDR='192.168.0.0/16'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-dataplane cilium \
  --network-plugin azure \
  --network-policy cilium \
  --network-plugin-mode overlay \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
      "networkProfile": {
  "networkProfile": {
    "networkDataplane": "cilium",
    "networkMode": null,
    "networkPlugin": "azure",
    "networkPluginMode": "overlay",
    "networkPolicy": "crd"
</pre>

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

```json
{
	"cniVersion": "0.3.1",
	"name": "cilium",
	"plugins": [
		{
			"type": "cilium-cni",
			"ipam": {
				"type": "azure-ipam"
			},
			"enable-debug": true,
			"log-file": "/var/log/cilium-cni.log"
		}
	]

```

While connecting to Calico Cloud

```console
2024-08-20T22:39:56+00:00 [error] Detected plugin cilium-cni, it is currently not supported
```

> [!WARNING]
> - Network policies work by default.

> [!NOTE]
> - Traffic goes out with the node ip address as source ip.
> - Traffic is not routeable to the pod using its IP address.

## BYOCNI - Calico - Overlay

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-byocni-calico-overlay'
K8S_VERSION=1.29
POD_CIDR='192.168.0.0/16'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin none \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
# install Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml
```

```bash
kubectl create -f - <<EOF
kind: Installation
apiVersion: operator.tigera.io/v1
metadata:
  name: default
spec:
  kubernetesProvider: AKS
  cni:
    type: Calico
  calicoNetwork:
    bgp: Disabled
    ipPools:
     - cidr: $POD_CIDR
       encapsulation: VXLAN
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
   name: default
spec: {}
EOF
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
      "networkProfile": {
  "networkProfile": {
    "networkDataplane": null,
    "networkMode": null,
    "networkPlugin": "none",
    "networkPluginMode": null,
    "networkPolicy": "none",
</pre>

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

```yaml
config file for Calico CNI plugin. Installed by calico/node.
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://10.0.0.1:443
    certificate-authority-data: "LS0tLS1CRUdJTiBDRVJUSU // truncated //UVORCBDRVJUSUZJQ0FURS0tLS0tCg=="
users:
- name: calico
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI // truncated  // Mf9p2zTE6Ke4rFO5eQwfDDZCi-SKdbsThB1kQE
contexts:
- name: calico-context
  context:
    cluster: local
    user: calico
current-context: calico-context
```

While connecting to Calico Cloud

```console
2024-08-21T16:37:34+00:00 [info] cluster_migratable:begin - Checking if cluster can be migrated
2024-08-21T16:37:39+00:00 [info] cluster_migratable:end - Cluster can be migrated
```

> [!WARNING]
> - Network policies work by default.

> [!NOTE]
> - Traffic goes out with the node ip address as source ip.
> - Traffic is not routeable to the pod using its IP address.

### BYOCNI - Calico

Create a v-net for the node and the pods.
192.168.0.0/16

```bash
CLUSTER_NAME='azcni-azure-byocni-calico'
POD_CIDR='192.168.0.0/16'
```

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --location $LOCATION \
  --nodepool-name 'linux' \
  --node-count 2 \
  --network-plugin none \
  --vnet-subnet-id /subscriptions/03cfb895-358d-4ad4-8aba-aeede8dbfc30/resourceGroups/rmartins/providers/Microsoft.Network/virtualNetworks/aks-virtual-network/subnets/default \
  --node-vm-size Standard_B2ms \
  --max-pods 70 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table
```

Getting credentials

```bash
az aks get-credentials --resource-group $RG --name $CLUSTER_NAME
```

```bash
# install Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/tigera-operator.yaml
```

```bash
kubectl create -f - <<EOF
apiVersion: projectcalico.org/v3
kind: IPReservation
metadata:
  name: ip-reservations
spec:
  reservedCIDRs:
  - 192.168.0.0/29
EOF
```

```bash
kubectl create -f - <<EOF
kind: Installation
apiVersion: operator.tigera.io/v1
metadata:
  name: default
spec:
  kubernetesProvider: AKS
  cni:
    type: Calico
  calicoNetwork:
    bgp: Enabled
    ipPools:
     - cidr: $POD_CIDR
       encapsulation: None
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
   name: default
spec: {}
EOF
```

```bash
az aks show --resource-group $RG --name $CLUSTER_NAME  | grep network
```

<pre>
WARNING: The behavior of this command has been altered by the following extension: aks-preview
      "networkProfile": {
  "networkProfile": {
    "networkDataplane": null,
    "networkMode": null,
    "networkPlugin": "none",
    "networkPluginMode": null,
    "networkPolicy": "none",
</pre>

```bash
VMSSGROUP=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $2}')
VMSSNAME=$(az vmss list --output table | grep -i $RG | grep -i $CLUSTER_NAME | awk -F ' ' '{print $1}')
az vmss run-command invoke -g $VMSSGROUP -n $VMSSNAME --scripts "cat /etc/cni/net.d/*" --command-id RunShellScript --instance-id 0 --query 'value[0].message' --output table
```

```yaml
config file for Calico CNI plugin. Installed by calico/node.
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://10.0.0.1:443
    certificate-authority-data: "LS0tLS1CRUdJTiBDRVJUSUZJQ0F // truncated //RVJUSUZJQ0FURS0tLS0tCg=="
users:
- name: calico
  user:
    token: eyJhbGciOiJSUzI1NiIsImt // truncated //hU_59mfdBpuOUeKqJ45p47zuELjXPMIqRGMrcJMJFcAFA
contexts:
- name: calico-context
  context:
    cluster: local
    user: calico
current-context: calico-context
```

While connecting to Calico Cloud

```console
2024-08-22T16:15:01+00:00 [info] cluster_migratable:end - Cluster can be migrated
2024-08-22T16:15:01+00:00 [info] cluster_migratable:end - Cluster can be migrated

2024-08-22T16:17:51Z    ERROR    Reconciler error    {"controller": "installer", "controllerGroup": "operator.calicocloud.io", "controllerKind": "Installer", "Installer": {"name":"default","namespace":"calico-cloud"}, "namespace": "calico-cloud", "name": "default", "reconcileID": "4416dffa-594d-457e-961c-b24dfff04e85", "error": "an error occurred while running the Calico Cloud installer: exit status 1"} sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler /go/pkg/mod/sigs.k8s.io/controller-runtime@v0.17.2/pkg/internal/controller/controller.go:329  sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem /go/pkg/mod/sigs.k8s.io/controller-runtime@v0.17.2/pkg/internal/controller/controller.go:266 sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2.2 /go/pkg/mod/sigs.k8s.io/controller-runtime@v0.17.2/pkg/internal/controller/controller.go:227
```

> [!WARNING]
> - Pods do not communicate between themselves.

> [!NOTE]
> - Need to test again.


## Testing

Test vm <-> pod traffic

Create a vm in the same RG/Vnet as the nodes.

```bash
sudo tcpdump -v -ni eth0 tcp port 7777 
```

Start a pod

```bash
kubectl run netshoot -it --rm --image nicolaka/netshoot -- /bin/bash
```

Command to test the connectivity

```bash
nc -zv <vm_ip_address> 7777
```

## Clean up

To delete the cluster

```bash
az aks delete --resource-group $RG --name $CLUSTER_NAME
```

> [!NOTE]
> If you created the vm for testing, you will need to delete the RG from the Azure console.

## Contributing

Feel free to contribute to this guide by:
1. Testing additional configurations
2. Documenting new findings
3. Reporting issues
4. Suggesting improvements