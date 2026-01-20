# 🚀 OCP-Adopter: UPI Node Provisioning Pattern

**The missing link for OpenShift UPI expansion.**

> 📖 **中文文档**: [简体中文](docs/README.zh.md) | **English** (current)

## 📖 Project Overview

This is an automation tool designed to standardize the process of adding new nodes in OpenShift UPI environments. It solves the three most challenging problems when manually adding nodes:

- **Network Configuration Inconsistency**: Automatically clones NetworkManager configurations from existing production nodes, ensuring routes and DNS are synchronized with the cluster.
- **Identity Conflicts**: Automatically generates globally unique UUIDs and injects hostnames to prevent network identity conflicts.
- **Environment Bootstrap Capability**: Innovatively adopts a "dual-state integrated" script design, enabling new nodes to have "self-healing" network capabilities in Live environments, thus successfully pulling remote Ignition credentials.

## 🎯 Key Features

- ✅ **One-Click Preparation**: Automatically extracts cluster credentials and generates Ignition configurations on the bastion host
- ✅ **Network Cloning**: Intelligently copies network configuration templates from existing nodes
- ✅ **Dual-State Design**: The same script supports both Server (preparation) and Client (installation) roles
- ✅ **Zero Manual Configuration**: New nodes only need to execute a single curl command to complete installation

## 🛠️ Usage

### ⚠️ Version Compatibility

**Important**: Ensure that the RHCOS Live ISO version matches your OpenShift cluster version. Different versions of RHCOS may be incompatible with the cluster, preventing nodes from joining properly.

- **OCP 4.x**: Requires RHCOS Live ISO of the corresponding version
- **OCP 5.x**: Requires RHCOS Live ISO of the corresponding version
- It is recommended to use the same RHCOS image version as existing nodes

### 📥 Obtaining RHCOS Live ISO

**Recommended Method**: Use the `openshift-install` command to obtain the RHCOS Live ISO download link that exactly matches your cluster version.

#### Step 1: Verify OpenShift Install Tool Version

```bash
openshift-install version
```

**Example Output:**
```
openshift-install 4.18.13
built from commit 9357b668a760d53a34f7094840d1e9f773127441
release image quay.io/openshift-release-dev/ocp-release@sha256:a93c65b0f9de1d2e29641fbeebc07178733db1cacc7bde178033d7b9183540bc
release architecture amd64
```

#### Step 2: Get RHCOS Live ISO Download Link

```bash
openshift-install coreos print-stream-json | grep '\.iso[^.]'
```

**Example Output:**
```
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/aarch64/rhcos-418.94.202501221327-0-live.aarch64.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/ppc64le/rhcos-418.94.202501221327-0-live.ppc64le.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/s390x/rhcos-418.94.202501221327-0-live.s390x.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/x86_64/rhcos-418.94.202501221327-0-live.x86_64.iso",
```

#### Step 3: Download ISO for Your Architecture

Based on your server architecture (usually `x86_64`), use `wget` or `curl` to download:

```bash
# x86_64 architecture (most common)
wget https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/x86_64/rhcos-418.94.202501221327-0-live.x86_64.iso

# Verify downloaded file size (typically around 1.2GB)
du -sh rhcos-*.iso
```

**Notes**:
- Ensure the `openshift-install` version matches your cluster version
- Select the ISO that matches your server architecture (x86_64, aarch64, ppc64le, or s390x)
- The downloaded ISO file size is typically around 1.2GB

### Prerequisites

- The bastion host must be able to access the OpenShift cluster (has executed `oc login`)
- New nodes must be able to access the bastion host's HTTP service (default port 8080)
- New nodes must mount a **RHCOS Live ISO image** that matches the cluster version

### Step 1: Prepare Configuration on Bastion Host

Execute the following command on the OCP cluster's bastion host:

```bash
sh ocp-node-tool.sh prepare <hostname> <IP/mask> <MAC address>
```

**Example:**

```bash
[root@registry add-node]# sh ocp-node-tool.sh prepare worker5 10.0.0.199/24 00:50:56:91:e2:cf
[LOG] 正在配置本地 HTTP 服务...
[LOG] 正在从集群提取凭据并注入主机名...
[LOG] 正在克隆现有节点网络配置...
[LOG] ------------------------------------------------
[LOG] ✅ 配置准备就绪！
[LOG] 请在新节点(Live ISO)执行以下命令进行安装：
curl -sL http://192.168.1.100:8080/worker5/install.sh | sudo bash -s install 192.168.1.100 worker5
[LOG] ------------------------------------------------
```

### Step 2: Execute Installation on New Node

1. **Mount RHCOS Live ISO**: Mount and boot the `rhcos-418.94.202501221327-0-live.x86_64.iso` in the virtual machine

2. **Execute Installation Command**: In the Live ISO terminal, execute the curl command output from Step 1:

```bash
curl -sL http://<bastion-IP>:8080/<hostname>/install.sh | sudo bash -s install <bastion-IP> <hostname>
```

3. **Wait for Installation to Complete**: After installation completes, remove the media and reboot. The virtual machine will automatically reboot twice during boot.

### Step 3: Approve Certificate Signing Requests (CSR)

Authorize CSRs using the `oc` command until all pending statuses disappear:

```bash
# Batch approve all pending CSRs
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve

# Check CSR status
oc get csr

# Verify node status
oc get node
```

**Expected Output:**

```
NAME      STATUS   ROLES                  AGE    VERSION
master1   Ready    control-plane,master   102d   v1.31.8
master2   Ready    control-plane,master   102d   v1.31.8
master3   Ready    control-plane,master   102d   v1.31.8
worker1   Ready    worker                 102d   v1.31.8
worker2   Ready    worker                 102d   v1.31.8
worker3   Ready    worker                 102d   v1.31.8
worker4   Ready    worker                 3h8m   v1.31.8
worker5   Ready    worker                 51s    v1.31.8
```

## 📋 How It Works

1. **Preparation Phase (Server Mode)**:
   - Extracts `worker-user-data-managed` Secret from OpenShift cluster
   - Injects custom hostname into Ignition configuration
   - Clones NetworkManager configuration template from existing nodes
   - Generates new UUID and replaces IP and MAC addresses
   - Starts HTTP service to provide configuration downloads

2. **Installation Phase (Client Mode)**:
   - Downloads network configuration file in Live ISO environment
   - Applies network configuration to enable node access to cluster
   - Uses `coreos-installer` to install RHCOS and apply Ignition configuration
   - Automatically reboots to complete node joining

## 🔧 Technical Details

- **Network Interface**: Defaults to `ens192` (can be modified via `INTERFACE` variable in script)
- **HTTP Port**: Defaults to 8080 (can be modified via `HTTP_PORT` variable in script)
- **Dependencies**: `jq`, `httpd`, `uuidgen`, `coreos-installer`

## 📝 Notes

- Ensure network connectivity between the bastion host and new nodes
- New node IP addresses must not conflict with existing nodes
- MAC addresses must be the actual MAC addresses of the new nodes
- Do not interrupt network connection during installation
- **Must use RHCOS Live ISO that matches the cluster version** - version mismatch may prevent nodes from joining the cluster

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.
