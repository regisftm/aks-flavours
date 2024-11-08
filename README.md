# AKS Flavours

Installation with different CNI's

|Parameter| Usage | Comments|
| --- | --- | --- |
| --network-dataplane | The network dataplane to use. Allowed values: **azure**, **cilium**. | Network dataplane used in the Kubernetes cluster. Specify "azure" to use the Azure dataplane (default) or "cilium" to enable Cilium dataplane.|
| --network-plugin | The Kubernetes network plugin to use.  Allowed values: **azure**, **kubenet**, **none**.| Specify "azure" for routable pod IPs from VNET, "kubenet" for non-routable pod IPs with an overlay network, or "none" for no networking configured.|
| --network-plugin-mode | The network plugin mode to use. Allowed values: **overlay**.| Used to control the mode the network plugin should operate in. For example, "overlay" used with **--network-plugin=azure** will use an overlay network (non-VNET IPs) for pods in the cluster.|
| --network-policy | (PREVIEW) The Kubernetes network policy to use.| Using together with "azure" network plugin. Specify "azure" for Azure network policy manager, "calico" for calico network policy controller, "cilium" for Azure CNI Overlay powered by Cilium. Defaults to "" (network policy disabled). |

## kubelet CNI

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-kubenet'
K8S_VERSION=1.29
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

# Azure CNI

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure'
K8S_VERSION=1.29
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

> [!WARNING]
> - Network policies do not work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.

## Azure CNI - Overlay

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-overlay'
K8S_VERSION=1.29
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

> [!WARNING]
> - Network policies do not work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with the node ip address as source ip.
> - Traffic is not routeable to the pod using its IP address.

## Azure CNI - Calico

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-calico'
K8S_VERSION=1.29
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

> [!WARNING]
> - Network policies work by default.
> - Network policies works after connect to Calico Cloud.

> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.


## Azure CNI - Cilium

Create a Vnet with 2 subnets - 1 for hosts, another for pods.
Create the cluster, referencing the node subnet using --vnet-subnet-id and the pod subnet using --pod-subnet-id and enabling cilium dataplane w/o overlay.

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-cilium'
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

While connecting to Calico Cloud

```console
2024-08-20T14:49:56+00:00 [error] Detected plugin cilium-cni, it is currently not supported
```

> [!WARNING]
> - Network policies work by default.


> [!NOTE]
> - Traffic goes out with pod ip address as source ip.
> - Also receive traffic on its own ip address from outside.

## Azure CNI - Cilium - Overlay

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-cilium-overlay'
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



## BYOCNI - Calico

Create a v-net for the node and the pods.
192.168.0.0/16

```bash
RG='rmartins'
LOCATION='westus2'
CLUSTER_NAME='azcni-azure-byocni-calico'
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