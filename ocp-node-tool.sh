[root@registry add-node]# cat ocp-node-tool.sh 
#!/bin/bash
# ocp-node-tool.sh - OpenShift 节点配置与安装一体化工具

# 全局配置
HTTP_PORT=8080
INTERFACE="ens192"

# --- 通用工具函数 ---
log() { echo -e "\033[1;32m[LOG]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# --- [Server 角色] 准备环境 ---
init_server_env() {
    log "正在配置本地 HTTP 服务..."
    sudo yum install -y jq httpd uuidgen &>/dev/null
    sudo sed -i "s/Listen 80$/Listen $HTTP_PORT/" /etc/httpd/conf/httpd.conf 2>/dev/null
    sudo systemctl enable --now httpd
}

# --- [Server 角色] 生成配置 ---
do_prepare() {
    local hn=$1; local ip_mask=$2; local mac=$3
    [ -z "$mac" ] && error "用法: $0 prepare <主机名> <IP/掩码> <MAC地址>"

    local web_path="/var/www/html/$hn"
    sudo mkdir -p "$web_path"

    init_server_env

    # 1. 生成 Ignition
    log "正在从集群提取凭据并注入主机名..."
    local raw_base64=$(oc get -n openshift-machine-api secret worker-user-data-managed -o jsonpath='{.data.userData}')
    [ -z "$raw_base64" ] && error "无法获取集群 Secret，请确保已 oc login"
    
    echo "$raw_base64" | base64 -d | jq --arg hn "$hn" '
      .storage.files |= (. // []) + [{
        "path": "/etc/hostname",
        "contents": { "source": "data:,\($hn)" },
        "mode": 420
      }]' > "${web_path}/${hn}-jq.ign"

    # 2. 抓取现有节点网络模板
    log "正在克隆现有节点网络配置..."
    local source_node=$(oc get nodes -l node-role.kubernetes.io/worker= --no-headers | grep " Ready" | head -n 1 | awk '{print $1}')
    [ -z "$source_node" ] && source_node=$(oc get nodes --no-headers | head -n 1 | awk '{print $1}')
    
    local tmp_file=$(mktemp)
    oc debug node/"$source_node" -- chroot /host cat /etc/NetworkManager/system-connections/${INTERFACE}.nmconnection > "$tmp_file" 2>/dev/null
    [ ! -s "$tmp_file" ] && error "无法从节点 $source_node 获取模板"

    # 3. 动态修改并保存
    local new_uuid=$(uuidgen)
    sed "s/^uuid=.*/uuid=${new_uuid}/" "$tmp_file" | \
    sed "s|^address0=.*|address0=${ip_mask}|" | \
    sed "s/^cloned-mac-address=.*/cloned-mac-address=${mac}/" > "${web_path}/${hn}-${INTERFACE}.nmconnection"
    
    sudo chmod -R 755 "$web_path"
    local srv_ip=$(hostname -I | awk '{print $1}')
    
    # 将脚本自身也拷贝到 web 目录，方便客户端下载
    sudo cp "$0" "$web_path/install.sh"

    log "------------------------------------------------"
    log "✅ 配置准备就绪！"
    log "请在新节点(Live ISO)执行以下命令进行安装："
    echo -e "\033[1;33mcurl -sL http://$srv_ip:$HTTP_PORT/$hn/install.sh | sudo bash -s install $srv_ip $hn\033[0m"
    log "------------------------------------------------"
}

# --- [Client 角色] 安装节点 ---
do_install() {
    local srv_ip=$1; local hn=$2
    [ -z "$hn" ] && error "用法: sudo $0 install <服务器IP> <主机名>"
    [ "$EUID" -ne 0 ] && error "请使用 sudo 执行安装"

    log "正在配置当前环境网络 (目标: $hn)..."
    local nm_file="${hn}-${INTERFACE}.nmconnection"
    local target_path="/etc/NetworkManager/system-connections/${INTERFACE}.nmconnection"
    
    curl -sL "http://${srv_ip}:${HTTP_PORT}/${hn}/${nm_file}" -o "$target_path" || error "下载网卡文件失败"
    
    chmod 600 "$target_path"
    nmcli connection load "$target_path"
    nmcli connection up "$INTERFACE"
    
    log "静态网络已生效，开始执行 coreos-installer..."
    local ign_url="http://${srv_ip}:${HTTP_PORT}/${hn}/${hn}-jq.ign"
    
    coreos-installer install /dev/sda \
        --copy-network \
        --ignition-url "$ign_url" \
        --insecure-ignition

    if [ $? -eq 0 ]; then
        log "🎉 安装成功！请移除介质并重启。"
    else
        error "安装失败"
    fi
}

# --- 主入口 ---
case "$1" in
    prepare)
        shift
        do_prepare "$@"
        ;;
    install)
        shift
        do_install "$@"
        ;;
    *)
        echo "OpenShift 节点自动化工具"
        echo "用法:"
        echo "  跳板机生成配置: $0 prepare <hostname> <ip/mask> <mac>"
        echo "  新节点执行安装: $0 install <server_ip> <hostname>"
        exit 1
        ;;
esac