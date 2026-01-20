# 🚀 OCP-Adopter: UPI Node Provisioning Pattern

**The missing link for OpenShift UPI expansion.**

> 📖 **English**: [English](../README.md) | **简体中文** (current)

## 📖 项目简介

这是一个旨在标准化 OpenShift UPI 环境下新增节点流程的自动化工具。它解决了手动添加节点时最头疼的三个问题：

- **网络配置不一致**：自动克隆现有生产节点的 NetworkManager 配置，确保路由、DNS 与集群同步。
- **标识冲突**：自动生成全局唯一 UUID 并注入主机名，防止网络标识冲突。
- **环境自举能力**：创新性地采用"双态一体化"脚本设计，使新节点在 Live 环境中具备"自愈"网络能力，从而顺利拉取远程 Ignition 凭据。

## 🎯 核心特性

- ✅ **一键准备**：在跳板机上自动提取集群凭据、生成 Ignition 配置
- ✅ **网络克隆**：智能复制现有节点的网络配置模板
- ✅ **双态设计**：同一脚本支持 Server（准备）和 Client（安装）两种角色
- ✅ **零手动配置**：新节点只需执行一条 curl 命令即可完成安装

## 🛠️ 使用方法

### ⚠️ 版本兼容性

**重要提示**：请确保使用的 RHCOS Live ISO 版本与您的 OpenShift 集群版本匹配。不同版本的 RHCOS 可能与集群不兼容，导致节点无法正常加入。

- **OCP 4.x**：需要使用对应版本的 RHCOS Live ISO
- 建议使用与现有节点相同版本的 RHCOS 镜像

### 📥 获取 RHCOS Live ISO

**推荐方法**：使用 `openshift-install` 命令获取与集群版本完全匹配的 RHCOS Live ISO 下载链接。

#### 步骤 1：确认 OpenShift 安装工具版本

```bash
openshift-install version
```

**示例输出：**

```
openshift-install 4.18.13
built from commit 9357b668a760d53a34f7094840d1e9f773127441
release image quay.io/openshift-release-dev/ocp-release@sha256:a93c65b0f9de1d2e29641fbeebc07178733db1cacc7bde178033d7b9183540bc
release architecture amd64
```

#### 步骤 2：获取 RHCOS Live ISO 下载链接

```bash
openshift-install coreos print-stream-json | grep '\.iso[^.]'
```

**示例输出：**

```
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/aarch64/rhcos-418.94.202501221327-0-live.aarch64.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/ppc64le/rhcos-418.94.202501221327-0-live.ppc64le.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/s390x/rhcos-418.94.202501221327-0-live.s390x.iso",
"location": "https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/x86_64/rhcos-418.94.202501221327-0-live.x86_64.iso",
```

#### 步骤 3：下载对应架构的 ISO

根据您的服务器架构（通常是 `x86_64`），使用 `wget` 或 `curl` 下载：

```bash
# x86_64 架构（最常见）
wget https://rhcos.mirror.openshift.com/art/storage/prod/streams/4.18-9.4/builds/418.94.202501221327-0/x86_64/rhcos-418.94.202501221327-0-live.x86_64.iso

# 验证下载文件大小（通常约 1.2GB）
du -sh rhcos-*.iso
```

**注意事项**：

- 确保 `openshift-install` 版本与您的集群版本匹配
- 选择与服务器架构匹配的 ISO（x86_64、aarch64、ppc64le 或 s390x）
- 下载的 ISO 文件大小通常约为 1.2GB

### 前置要求

- 跳板机需要能够访问 OpenShift 集群（已执行 `oc login`）
- 新节点需要能够访问跳板机的 HTTP 服务（默认端口 8080）
- 新节点需要挂载与集群版本匹配的 **RHCOS Live ISO 镜像**

### 步骤 1：在跳板机上准备配置

在 OCP 集群的跳板机上执行以下命令：

```bash
sh ocp-node-tool.sh prepare <主机名> <IP/掩码> <MAC地址>
```

**示例：**

```bash
[root@registry add-node]# sh ocp-node-tool.sh prepare worker5 172.168.21.199 00:50:56:91:e2:cf
[LOG] 正在配置本地 HTTP 服务...
[LOG] 正在从集群提取凭据并注入主机名...
[LOG] 正在克隆现有节点网络配置...
[LOG] ------------------------------------------------
[LOG] ✅ 配置准备就绪！
[LOG] 请在新节点(Live ISO)执行以下命令进行安装：
curl -sL http://192.168.2.18:8080/worker5/install.sh | sudo bash -s install 192.168.2.18 worker5
[LOG] ------------------------------------------------
```

### 步骤 2：在新节点上执行安装

1. **挂载 RHCOS Live ISO**：在虚拟机中挂载并引导启动 `rhcos-418.94.202501221327-0-live.x86_64.iso`
2. **执行安装命令**：在 Live ISO 的终端中执行步骤 1 中输出的 curl 命令：

```bash
curl -sL http://<跳板机IP>:8080/<主机名>/install.sh | sudo bash -s install <跳板机IP> <主机名>
```

3. **等待安装完成**：安装完成后，移除介质并重启。虚拟机引导时会自动重启 2 次。

### 步骤 3：批准证书签名请求（CSR）

通过 `oc` 命令授权 CSR，直到所有 pending 状态消失：

```bash
# 批量批准所有待处理的 CSR
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve

# 检查 CSR 状态
oc get csr

# 验证节点状态
oc get node
```

**预期输出：**

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

## 📋 工作原理

1. **准备阶段（Server 模式）**：

   - 从 OpenShift 集群提取 `worker-user-data-managed` Secret
   - 注入自定义主机名到 Ignition 配置
   - 从现有节点克隆 NetworkManager 配置模板
   - 生成新的 UUID 并替换 IP、MAC 地址
   - 启动 HTTP 服务提供配置下载
2. **安装阶段（Client 模式）**：

   - 在 Live ISO 环境中下载网络配置文件
   - 应用网络配置使节点能够访问集群
   - 使用 `coreos-installer` 安装 RHCOS 并应用 Ignition 配置
   - 自动重启完成节点加入

## 🔧 技术细节

- **网络接口**：默认使用 `ens192`（可在脚本中修改 `INTERFACE` 变量）
- **HTTP 端口**：默认 8080（可在脚本中修改 `HTTP_PORT` 变量）
- **依赖工具**：`jq`、`httpd`、`uuidgen`、`coreos-installer`

## 📝 注意事项

- 确保跳板机和新节点之间的网络连通性
- 新节点的 IP 地址不能与现有节点冲突
- MAC 地址必须是新节点的实际 MAC 地址
- 安装过程中请勿中断网络连接
- **必须使用与集群版本匹配的 RHCOS Live ISO**，版本不匹配可能导致节点无法加入集群

## 📄 许可证

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.
