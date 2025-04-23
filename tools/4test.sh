#!/bin/bash

# Copyright (2024, ) Institute of Software, Chinese Academy of Sciences
#
# @author: liujiexin@otcaix.iscas.ac.cn
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# 设置基本工作目录
export PKGPWD=$(pwd)
# 引入 kubez-ansible 和 base.sh
export KUBEZ_ANSIBLE_DIR="${PKGPWD}/kubez-ansible-offline-master"


# 设置 INVENTORY 变量
if [ -z "${INVENTORY}" ]; then
    export INVENTORY="${BASEDIR}/ansible/inventory/all-in-one"
fi

# 从 base.sh 获取一些有用的变量
[ -z "${LOCALIP}" ] && LOCALIP=${IP_ADDRESS}
[ -z "${IMAGETAG}" ] && IMAGETAG=${KUBE_VERSION}

# 打印日志函数
function log() {
    # 获取调用者的行号和文件名
    local caller_info=$(caller 0)
    local line_number=$(echo "$caller_info" | awk '{print $1}')
    local file_name=$(basename $(echo "$caller_info" | awk '{print $2}'))
    
    # 获取当前时间
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $1 in
        "info")
            echo -e "${timestamp} [${file_name}:${line_number}] \e[32m[ INFO ]\e[0m $2"
            ;;
        "error")
            echo -e "${timestamp} [${file_name}:${line_number}] \e[31m[ ERROR ]\e[0m $2"
            ;;
        *)
            echo -e "${timestamp} [${file_name}:${line_number}] \e[34m[ INFO ]\e[0m $2"
            ;;
    esac
}

# 设置基础目录
function set_base_dir() {
    if [[ -z "$SNAP" ]]; then
        if [[ -d "/usr/share/kubez-ansible" ]]; then
            export BASEDIR="/usr/share/kubez-ansible"
        elif [[ -d "/usr/local/share/kubez-ansible" ]]; then
            export BASEDIR="/usr/local/share/kubez-ansible"
        elif [[ -n ${VIRTUAL_ENV} ]] && [[ -d "${VIRTUAL_ENV}/share/kubez-ansible" ]]; then
            export BASEDIR="${VIRTUAL_ENV}/share/kubez-ansible"
        else
            export BASEDIR="${KUBEZ_ANSIBLE_DIR}"
        fi
    else
        export BASEDIR="$SNAP/share/kubez-ansible"
    fi
}

# 在 init_env 函数之前添加 ALL_IN_ONE 变量的设置


# 添加检查系统版本的函数
function check_system_version() {
    log info "检查系统版本..."
    
    # 检查是否为 CentOS 系统
    if [ ! -f "/etc/centos-release" ]; then
        log error "当前仅支持 CentOS 系统"
        exit 1
    }
    
    # 获取完整的系统版本信息
    local full_version=$(cat /etc/centos-release)
    
    # 检查是否为 CentOS 7.9
    if ! echo "$full_version" | grep -q "CentOS Linux release 7.9"; then
        log error "当前仅支持 CentOS 7.9 版本"
        log error "检测到系统版本为: ${full_version}"
        exit 1
    }
    
    # 获取具体的小版本号
    local full_version=$(cat /etc/centos-release | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    log info "系统版本检查通过: CentOS ${full_version}"
    
    # 检查系统架构
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        log error "当前仅支持 x86_64 架构，检测到系统架构为 ${arch}"
        exit 1
    }
    log info "系统架构检查通过: ${arch}"
    
    # 检查系统内核版本
    local kernel_version=$(uname -r)
    log info "当前系统内核版本: ${kernel_version}"
    
    # 检查 SELinux 状态
    local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
    if [ "$selinux_status" = "Enforcing" ]; then
        log error "请先禁用 SELinux"
        exit 1
    fi
    log info "SELinux 状态检查通过: ${selinux_status}"
    
    return 0
}

# 修改 init_env 函数，添加系统版本检查
function init_env() {
    # 首先检查内存
    check_memory
    
    # 然后检查系统版本
    check_system_version
    
    # 设置基础目录
    set_base_dir
    
    # 自动获取网络接口和IP地址
    NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}')
    IP_ADDRESS=$(ip addr show ${NETWORK_INTERFACE} | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

    # 设置环境变量
    export KUBE_VERSION="1.23.17"
    # 允许用户自定义Harbor端口，默认为8080
    export HARBOR_PORT=${HARBOR_PORT:-8080}
    
    # 检查Harbor端口是否为禁用端口
    if [ "$HARBOR_PORT" = "58000" ] || [ "$HARBOR_PORT" = "58001" ]; then
        log error "Harbor端口不能设置为58000或58001，这些端口已被系统保留"
        exit 1
    fi
    # 输出所有的配置参数
    
    export LOCAL_REGISTRY="${IP_ADDRESS}:${HARBOR_PORT}/pixiuio"
    export YUM_REPO="http://${IP_ADDRESS}:58000/repository/pixiuio-centos"
    export CONTAINER_REGISTRY="${IP_ADDRESS}:${HARBOR_PORT}"
    export RPMURL="http://${IP_ADDRESS}:58000/repository/pixiuio-centos/repodata/repomd.xml"
 

    # 设置文件路径
    export BASE_FILES_DIR="${PKGPWD}"
    export OTHERS_DIR="${PKGPWD}/others"
    export IMAGE_DIR="${PKGPWD}/image"
    export ALL_IN_ONE="${PKGPWD}/kubez-ansible-offline-master/ansible/inventory/all-in-one"
    
    # 设置 Ansible 相关变量
    export ANSIBLE_HOST_KEY_CHECKING=False
    export ANSIBLE_LOG_PATH=/var/log/ansible.log
    
}

# 添加关闭防火墙的函数
function disable_firewall() {
    log info "检查并关闭防火墙..."
    
    # 检查 firewalld 是否安装
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        log info "firewalld 未安装，无需关闭"
        return 0
    fi
    
    # 检查 firewalld 服务状态
    if systemctl is-active firewalld >/dev/null 2>&1; then
        log info "停止 firewalld 服务..."
        if ! systemctl stop firewalld; then
            log error "停止 firewalld 服务失败"
            exit 1
        fi
        
        log info "禁用 firewalld 开机自启..."
        if ! systemctl disable firewalld; then
            log error "禁用 firewalld 开机自启失败"
            exit 1
        fi
        
        log info "firewalld 服务已停止并禁用"
    else
        log info "firewalld 服务未运行"
        
        # 确保 firewalld 开机自启被禁用
        if systemctl is-enabled firewalld >/dev/null 2>&1; then
            log info "禁用 firewalld 开机自启..."
            if ! systemctl disable firewalld; then
                log error "禁用 firewalld 开机自启失败"
                exit 1
            fi
        fi
    fi
    
    return 0
}

# 检查端口是否被占用
function check_port_usage() {
    local port=$1
    local timeout=1  # 设置超时时间为1秒
    
    log info "检查端口 ${port} 是否被占用..."
    
    # 使用 ss 命令检查端口占用
    if ss -Hln "sport = :${port}" | grep -q ":${port}"; then
        log error "端口 ${port} 已被占用"
        return 1
    fi
    
    # 使用 /dev/tcp 进行双重检查
    if timeout ${timeout} bash -c "</dev/tcp/127.0.0.1/${port}" &>/dev/null; then
        log error "端口 ${port} 已被占用"
        return 1
    fi
    
    log info "端口 ${port} 可用"
    return 0
}

# 检查所需端口是否可用
function check_ports_availability() {
    log info "检查必要端口是否可用..."
    
    # 定义需要检查的端口列表及其用途
    declare -A ports=(
        [58000]="Nexus 服务端口"
        [58001]="Harbor 仓库端口"
        [${HARBOR_PORT}]="Harbor 服务端口"
        [6443]="Kubernetes API 端口"
        [2379]="etcd 客户端端口"
        [2380]="etcd 服务器端口"
        [10250]="Kubelet API 端口"
        [10251]="kube-scheduler 端口"
        [10252]="kube-controller-manager 端口"
        [10255]="Kubelet 只读端口"
    )
    
    local port_check_failed=0
    
    # 检查每个端口
    for port in "${!ports[@]}"; do
        log info "检查 ${ports[$port]} (${port})"
        if ! check_port_usage "${port}"; then
            log error "${ports[$port]} (${port}) 被占用"
            port_check_failed=1
        fi
    done
    
    # 如果有端口被占用，则退出
    if [ ${port_check_failed} -eq 1 ]; then
        log error "存在端口冲突，请解决后重试"
        return 1
        fi
    
    log info "所有必要端口均可用"
    return 0
}

# 等待端口就绪
function wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-300}  # 默认超时时间为300秒
    local interval=${4:-5}   # 默认检查间隔为5秒
    local description=${5:-"服务"}  # 端口描述，默认为"服务"
    
    log info "等待 ${description} ${host}:${port} 就绪..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [ $(date +%s) -lt ${end_time} ]; do
        if timeout 2 bash -c "</dev/tcp/${host}/${port}" &>/dev/null; then
            log info "${description} ${host}:${port} 已就绪"
            return 0
        fi
        log info "等待 ${description} ${host}:${port} 就绪中...(剩余 $((end_time - $(date +%s))) 秒)"
        sleep ${interval}
    done
    
    log error "${description} ${host}:${port} 等待超时"
    return 1
}

# 示例使用：在安装服务前检查端口
function pre_install_check() {
    log info "执行安装前检查..."
    
    # 检查所有必需端口
    if ! check_ports_availability; then
        log error "端口检查失败，无法继续安装"
            exit 1
        fi
    
    log info "安装前检查完成"
    return 0
}

# 在安装 Nexus 后等待服务就绪
function wait_nexus_ready() {
    log info "等待 Nexus 服务就绪..."
    
    # 等待 Nexus 端口就绪
    if ! wait_for_port "localhost" "58000" 300 5 "Nexus"; then
        log error "Nexus 服务启动失败"
        exit 1
    fi
    
    log info "Nexus 服务已就绪"
    return 0
}

# 在安装 Harbor 后等待服务就绪
function wait_harbor_ready() {
    log info "等待 Harbor 服务就绪..."
    
    # 等待 Harbor 端口就绪
    if ! wait_for_port "localhost" "${HARBOR_PORT}" 300 5 "Harbor"; then
        log error "Harbor 服务启动失败"
        exit 1
    fi
    
    log info "Harbor 服务已就绪"
    return 0
}

# 检查内存
function check_memory() {
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_total_gb=$(echo "scale=2; $mem_total_kb / 1024 / 1024" | bc)
    required_mem_gb=4.0

    if (( $(echo "$mem_total_gb < $required_mem_gb" | bc -l) )); then
        log error "内存不足: 当前系统内存为 ${mem_total_gb}GB，需要至少 ${required_mem_gb}GB 内存"
        exit 1
    fi
    log info "内存检查通过: 当前系统内存为 ${mem_total_gb}GB"
}

# 检查必要文件
function check_files() {
    local files=(
        "${BASE_FILES_DIR}/k8s-centos7-v${KUBE_VERSION}_images.tar.gz"
        "${BASE_FILES_DIR}/k8s-centos7-v${KUBE_VERSION}-rpm.tar.gz"
        "${BASE_FILES_DIR}/kubez-ansible-offline-master.zip"
        "${BASE_FILES_DIR}/nexus.tar.gz"
        "${BASE_FILES_DIR}/others.tar.gz"
        "${BASE_FILES_DIR}/image.tar.gz"
    )

    # 检查目录是否干净
    log info "检查目录是否干净"
    local current_items=(${PKGPWD}/*)
    local illegal_items=()
    
    for current_item in "${current_items[@]}"; do
        # 跳过当前脚本文件
        if [ "$(basename ${current_item})" = "$(basename $0)" ]; then
            continue
        fi
        
        # 检查是否为目录 - 目录在解压前应该不存在
        if [ -d "${current_item}" ]; then
            illegal_items+=("目录: $(basename ${current_item})")
            continue
        fi
        
        # 检查文件
        local is_allowed_file=false
        for allowed_file in "${files[@]}"; do
            if [ "${current_item}" = "${allowed_file}" ]; then
                is_allowed_file=true
                break
            fi
        done
        
        if [ "$is_allowed_file" = false ]; then
            illegal_items+=("文件: $(basename ${current_item})")
        fi
    done
    
    # 如果存在非法项目，一次性输出所有并退出
    if [ ${#illegal_items[@]} -gt 0 ]; then
        log error "发现以下非法项目:"
        for illegal_item in "${illegal_items[@]}"; do
            log error "  - ${illegal_item}"
        done
        log error "目录必须只包含必要的压缩包文件"
        exit 1
    fi
    
    log info "目录检查通过"

    # 检查必要文件是否存在
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            log error "$(basename ${file}) 不存在"
            exit 1
        fi
    done

    # 解压others.tar.gz
    if [ ! -d "${OTHERS_DIR}" ]; then
        log info "解压 others.tar.gz..."
        tar -zxvf "${BASE_FILES_DIR}/others.tar.gz" || { log error "解压 others.tar.gz 失败"; exit 1; }
    fi
    if [ ! -d "${IMAGE_DIR}" ]; then
        log info "解压 image.tar.gz..."
        tar -zxvf "${BASE_FILES_DIR}/image.tar.gz" || { log error "解压 others.tar.gz 失败"; exit 1; }
    fi

    # 检查others目录下的文件
    local others_files=(
        "${OTHERS_DIR}/prometheus-pv.yaml"
        "${OTHERS_DIR}/prometheus.yaml"
        "${OTHERS_DIR}/grafana-pv.yaml"
        "${OTHERS_DIR}/grafana.yaml"
        "${OTHERS_DIR}/install.sh"
        "${OTHERS_DIR}/harbor"
        "${OTHERS_DIR}/uni-virt"
    )

    for file in "${others_files[@]}"; do
        if [ ! -e "${file}" ]; then
            log error "$(basename ${file}) 不存在"
            exit 1
        fi
    done

    log info "文件检查完成"
}

# 安装nexus
function install_nexus() {
    # 检查是否已安装
    if [ -d "/data/nexus_local" ]; then
        log info "Nexus 目录已存在"
    else
        log info "准备开始安装 Nexus"
        mkdir -p /data
        tar -zxvf nexus.tar.gz -C /data || { log error "解压nexus.tar.gz失败"; exit 1; }
    fi

    cd /data/nexus_local && bash nexus.sh start || { log error "启动nexus服务失败"; exit 1; }

    if ! grep -q "bash nexus.sh start" /etc/rc.d/rc.local; then
        chmod +x /etc/rc.d/rc.local
        echo 'cd /data/nexus_local && bash nexus.sh start' >> /etc/rc.d/rc.local
    fi

    # 等待 Nexus 服务启动
    wait_nexus_ready
}

# 修改 process_materials 函数，在加载镜像前添加 Docker 安装和启动
function process_materials() {
    cd ${PKGPWD}
    
    
    # 处理镜像
    if [ ! -d "allimagedownload" ]; then
        log info "开始解压远程镜像文件"
        tar -zxvf k8s-centos7-v${KUBE_VERSION}_images.tar.gz || { log error "解压镜像文件失败"; exit 1; }
    fi

    # 解压RPM包
    if [ ! -d "localrepo" ]; then
        log info "开始解压RPM包"
        tar -zxvf k8s-centos7-v${KUBE_VERSION}-rpm.tar.gz || { log error "解压RPM包失败"; exit 1; }
    fi

    # 解压本地镜像文件
    if [ ! -d "image" ]; then
        log info "开始解压本地镜像文件"
        tar -zxvf image.tar.gz || { log error "解压镜像文件失败"; exit 1; }
    fi

    # 2. 上传远程镜像和RPM包
    log info "上传远程镜像和RPM包..."
    cd allimagedownload && sh load_image.sh ${IP_ADDRESS} || { log error "加载远程镜像失败"; exit 1; }
    cd ../localrepo && sh push_rpm.sh ${IP_ADDRESS} || { log error "推送RPM包失败"; exit 1; }
    cd ${PKGPWD}

    # 3. 检查 RPM 仓库状态
    wait_nexus_ready

    # 4. 配置YUM源
    log info "配置YUM源..."
    setup_yum_repo || { log error "配置YUM源失败"; exit 1; }

    # 7. 检查并安装 Docker
    log info "检查并安装 Docker..."
    setup_docker || {
        log error "Docker 安装和配置失败"
        exit 1
    }

    # 5. 最后加载本地镜像
    log info "加载本地镜像..."
    if [ -d "image" ] && [ -f "image/load.sh" ]; then
        cd "image" && sh load.sh || { log error "加载本地镜像失败"; exit 1; }
        cd ${PKGPWD}
        fi

    log info "所有材料处理完成"
}

# 添加安装和配置 Docker 的函数
function setup_docker() {
    log info "检查并安装 Docker..."
    
    # 1. 首先检查 Docker 是否已安装且运行正常
    if command -v docker &>/dev/null; then
        if check_docker_status; then
            log info "Docker 已安装且运行正常"
            return 0
    else
            log info "检测到 Docker 已安装但未正常运行，尝试修复..."
            systemctl stop docker || true
            systemctl disable docker || true
        fi
    fi

    # 2. 检查 RPM 包是否可用
    log info "检查 Docker RPM 包是否可用..."
    if ! check_docker_rpms; then
        log error "Docker RPM 包检查失败，无法继续安装"
        exit 1
    fi

    # 3. 安装基础依赖包
    log info "安装基础依赖包..."
    yum install -y yum-utils device-mapper-persistent-data lvm2 || {
        log error "安装基础依赖包失败"
            exit 1
        }

    # 3. 安装 Docker CE 及其组件
    log info "安装 Docker CE 及其组件..."
    yum install -y docker-ce docker-ce-cli containerd.io || {
        log error "Docker 安装失败，请检查 YUM 源配置"
        exit 1
    }

    # 4. 配置 Docker daemon
    log info "配置 Docker daemon..."
    mkdir -p /etc/docker
    
    # 备份现有的 daemon.json（如果存在）
    if [ -f "/etc/docker/daemon.json" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="/etc/docker/daemon.json.bak.${timestamp}"
        log info "备份现有的 daemon.json 到 ${backup_file}"
        cp -f "/etc/docker/daemon.json" "${backup_file}"
    fi
    
    # 创建新的 daemon.json
    log info "创建新的 daemon.json 配置文件..."
    cat > /etc/docker/daemon.json <<EOF
{
    "insecure-registries": ["0.0.0.0/0"],
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

    # 5. 启动 Docker 服务
    log info "启动 Docker 服务..."
    systemctl daemon-reload
    systemctl enable docker
    if ! systemctl start docker; then
        log error "Docker 服务启动失败，查看详细错误信息："
        journalctl -xeu docker --no-pager | tail -n 50
        exit 1
    fi

    # 7. 验证安装
    log info "验证 Docker 安装..."
    local max_retries=30
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if check_docker_status; then
            log info "Docker 安装成功并正常运行"
            docker version
            return 0
        fi
        log info "等待 Docker 服务就绪... (${retry_count}/${max_retries})"
        sleep 2
        ((retry_count++))
    done
    
    log error "Docker 服务启动超时"
    exit 1
}

# 添加一个用于检查 Docker 运行状态的辅助函数
function check_docker_status() {
    log info "检查 Docker 运行状态..."
    
    # 检查 Docker 守护进程是否运行
    if ! systemctl is-active docker &>/dev/null; then
    
        return 1
    fi

    # 检查 Docker 命令是否可用
    if ! docker version &>/dev/null; then
        log error "Docker 命令执行失败"
        return 1
    fi


    log info "Docker 运行状态正常"
    return 0
}

# 添加一个新函数用于检查 RPM 包是否存在
function check_docker_rpms() {
    log info "检查 Docker RPM 包是否存在..."
    local required_rpms=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
    )

    for rpm in "${required_rpms[@]}"; do
        if ! yum list available "$rpm" &>/dev/null; then
            log error "找不到 $rpm 包，请确保 YUM 源中包含该包"
            return 1
        fi
    done
    return 0
}

# 配置YUM仓库
function setup_yum_repo() {
    log info "配置YUM仓库"
    
    # 备份原有YUM仓库配置
    if [ -d "/etc/yum.repos.d" ]; then
        # 创建带时间戳的备份目录
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_dir="/etc/yum.repos.d.bak.${timestamp}"
        log info "备份原有YUM仓库配置到 ${backup_dir}"
        mkdir -p "${backup_dir}" || { log error "创建备份目录失败"; exit 1; }
        
        # 复制所有仓库文件到备份目录
        cp -rf /etc/yum.repos.d/* "${backup_dir}/" 2>/dev/null || log info "没有仓库文件需要备份"
        
        # 完全删除并重新创建仓库目录，确保干净
        rm -rf /etc/yum.repos.d
        mkdir -p /etc/yum.repos.d || { log error "创建YUM仓库目录失败"; exit 1; }
        
        # 设置目录权限
        chmod 755 /etc/yum.repos.d
    else
        # 如果仓库目录不存在，创建新目录
        log info "创建YUM仓库目录"
        mkdir -p /etc/yum.repos.d || { log error "创建YUM仓库目录失败"; exit 1; }
        chmod 755 /etc/yum.repos.d
    fi

    # 创建离线仓库配置文件
    log info "创建离线仓库配置文件"
    cat > /etc/yum.repos.d/offline.repo <<EOF
[basenexus]
name=Pixiuio Repository
baseurl=${YUM_REPO}
enabled=1
gpgcheck=0
EOF
    chmod 644 /etc/yum.repos.d/offline.repo
    
    # 清理缓存并重建
    log info "清理YUM缓存并重建"
    yum clean all && yum makecache || { log error "YUM缓存重建失败"; exit 1; }
    log info "YUM仓库配置完成"
}

# 配置 kubez-ansible 免密登录
function setup_kubez_ansible_auth() {
    log info "配置 kubez-ansible 免密登录"
    
    # 检查 /root/.ssh 目录
    if [ ! -d "/root/.ssh" ]; then
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
    fi

    # 生成 SSH 密钥（如果不存在）
    if [ ! -f "/root/.ssh/id_rsa" ]; then
        log info "生成 SSH 密钥对"
        ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa || { log error "生成 SSH 密钥失败"; exit 1; }
    fi


    # 执行免密登录配置
    log info "执行免密登录配置"
    kubez-ansible authorized-key || { log error "配置免密登录失败"; exit 1; }

    # 验证免密登录配置
    log info "验证免密登录配置"
    
    if ! ansible -i "${ALL_IN_ONE}" all -m ping; then
        log error "免密登录验证失败"
        exit 1
    fi

    log info "kubez-ansible 免密登录配置完成"
}

# 安装kubez-ansible
function install_kubez_ansible() {
    cd ${PKGPWD}
    if [ ! -d "kubez-ansible-offline-master" ]; then
        log info "解压kubez-ansible-offline-master.zip"
        unzip -o kubez-ansible-offline-master.zip || { log error "解压kubez-ansible-offline-master.zip失败"; exit 1; }
    fi

    yum -y install ansible unzip python2-pip || { log error "安装基础包失败"; exit 1; }
    
    cd kubez-ansible-offline-master
    pip install pip/pbr-5.11.1-py2.py3-none-any.whl || { log error "安装pbr失败"; exit 1; }
    
    cp tools/git /usr/local/bin && chmod 755 /usr/local/bin/git && git init
    python setup.py install || { log error "安装kubez-ansible失败"; exit 1; }
    
    cp -rf etc/kubez/ /etc/kubez
    cd ${PKGPWD}

    # 配置免密登录
    setup_kubez_ansible_auth
}

# 配置kubernetes环境
function setup_kubernetes() {
    # 创建必要目录
    mkdir -p /etc/kubez
    mkdir -p /data/prometheus /data/grafana

    # 检查并备份 globals.yml
    if [ -f "/etc/kubez/globals.yml" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        cp -f /etc/kubez/globals.yml "/etc/kubez/globals.yml.bak.${timestamp}" || { log error "备份 globals.yml 失败"; exit 1; }
    fi

    # 使用新的配置文件
    cp -f "${PKGPWD}/kubez-ansible-offline-master/etc/kubez/globals.yml" /etc/kubez/globals.yml || { log error "复制新的 globals.yml 失败"; exit 1; }

    # 修改 globals.yml 配置
    sed -i "s/kube_release: .*/kube_release: ${KUBE_VERSION}/g" /etc/kubez/globals.yml
    sed -i "s/network_interface: .*/network_interface: \"${NETWORK_INTERFACE}\"/g" /etc/kubez/globals.yml
    sed -i "s|image_repository: .*|image_repository: \"${LOCAL_REGISTRY}\"|g" /etc/kubez/globals.yml
    sed -i "s|yum_baseurl: .*|yum_baseurl: \"${YUM_REPO}\"|g" /etc/kubez/globals.yml
    sed -i "s|image_repository_container: .*|image_repository_container: \"${CONTAINER_REGISTRY}\"|g" /etc/kubez/globals.yml
    sed -i "s/cluster_cidr: .*/cluster_cidr: \"172.30.0.0\/16\"/g" /etc/kubez/globals.yml
    sed -i "s/service_cidr: .*/service_cidr: \"10.254.0.0\/16\"/g" /etc/kubez/globals.yml

    # 执行Kubernetes安装
    kubez-ansible bootstrap-servers || { log error "bootstrap-servers 执行失败"; exit 1; }
    kubez-ansible deploy || { log error "deploy 执行失败"; exit 1; }

}

# 等待kubernetes集群就绪
function wait_kubernetes_ready() {
    log info "等待集群就绪..."
    local max_retries=60
    local count=0

    while [ $count -lt $max_retries ]; do
        # 检查所有节点是否就绪
        if ! kubectl get nodes --no-headers | grep -v "Ready" | grep -v "NAME" > /dev/null; then
                log info "集群已就绪"
                return 0
        fi

        log info "等待集群就绪中...(${count}/${max_retries})"
        sleep 10
        ((count++))
    done

    log error "等待集群就绪超时"
    exit 1
}

# 安装监控组件
function install_monitoring() {
    log info "检查 Kubernetes 集群状态"
    check_kubernetes_ready
    
    log info "安装 Prometheus 和 Grafana"
    cd "${OTHERS_DIR}" || { log error "进入${OTHERS_DIR}目录失败"; exit 1; }
    kubectl apply -f prometheus-pv.yaml || { log error "应用prometheus-pv.yaml失败"; exit 1; }
    kubectl apply -f prometheus.yaml || { log error "应用prometheus.yaml失败"; exit 1; }
    kubectl apply -f grafana-pv.yaml || { log error "应用grafana-pv.yaml失败"; exit 1; }
    kubectl apply -f grafana.yaml || { log error "应用grafana.yaml失败"; exit 1; }
    cd "${PKGPWD}"
}

# 检查Harbor地址是否可以ping通
function check_harbor_connectivity() {
    log info "检查Harbor地址 ${IP_ADDRESS} 是否可以ping通"
    
    # 首先检查IP是否可以ping通
    if ! ping -c 3 ${IP_ADDRESS} > /dev/null 2>&1; then
        log error "Harbor地址 ${IP_ADDRESS} 无法ping通，请检查网络配置"
        exit 1
    fi
    
    log info "Harbor地址 ${IP_ADDRESS} 可以ping通，检查Harbor服务端口..."
    
    # 从harbor.yml获取HTTP端口
    local harbor_yml="${OTHERS_DIR}/harbor/harbor.yml"
    if [ ! -f "$harbor_yml" ]; then
        harbor_yml="/usr/local/harbor/harbor.yml"
    fi
    
    if [ -f "$harbor_yml" ]; then
        # 提取HTTP端口
        local http_port=$(grep -A 2 "^http:" "$harbor_yml" | grep "port:" | awk '{print $2}')
        if [ -z "$http_port" ]; then
            http_port="${HARBOR_PORT}" # 使用环境变量中的端口
            log info "无法从harbor.yml获取HTTP端口，使用环境变量设置的端口: ${http_port}"
        fi
        
        # 检查端口连通性
        if curl -s -m 5 ${IP_ADDRESS}:${http_port} > /dev/null 2>&1; then
            log info "Harbor服务端口 ${http_port} 可以访问"
            return 0
        else
            log error "Harbor服务端口 ${http_port} 无法访问，请检查Harbor服务是否正常运行"
            exit 1
        fi
    else
        log error "找不到harbor.yml配置文件，无法获取Harbor端口信息"
        exit 1
    fi
}

# 安装Harbor
function install_harbor() {
    log info "安装 Harbor"
    cd "${OTHERS_DIR}/harbor" || { log error "进入harbor目录失败"; exit 1; }

    # Stop and clean up existing Harbor installation
    if systemctl is-active harbor &>/dev/null; then
        log info "停止现有 Harbor 服务"
        systemctl stop harbor
        sleep 10
    fi

    if [ -d "/usr/local/harbor" ]; then
        log info "清理旧的 Harbor 安装"
        cd /usr/local/harbor
        docker-compose down -v || true
        cd "${OTHERS_DIR}/harbor"
        rm -rf /usr/local/harbor
    fi

    # 创建必要的目录
    mkdir -p /var/log/harbor /data/registry /data/database /data/redis || { log error "创建必要目录失败"; exit 1; }
    chmod 755 /var/log/harbor /data/registry /data/database /data/redis
    chown -R 10000:10000 /data/

    # 先复制整个目录到 /usr/local
    log info "复制 Harbor 目录到 /usr/local"
    cp -r "${OTHERS_DIR}/harbor" /usr/local/ || { log error "复制harbor目录失败"; exit 1; }
    
    # 进入目标目录进行配置
    cd /usr/local/harbor || { log error "进入/usr/local/harbor目录失败"; exit 1; }
    
    # # 配置 Harbor
    # if [ -f "harbor.yml" ]; then
    #     log info "删除旧的harbor.yml"
    #     rm -f harbor.yml
    # fi
    # cp -f harbor.yml.tmpl harbor.yml || { log error "复制harbor配置文件失败"; exit 1; }
    # sed -i "s/hostname: reg.mydomain.com/hostname: ${IP_ADDRESS}/g" harbor.yml
    sed -i "/^http:/,/^[^[:space:]]/{s/^  port: 8080/  port: ${HARBOR_PORT}/}" harbor.yml
    
    # # 注释掉 https 部分（包括其下所有缩进的配置）
    # sed -i '/^https:/,/^[^[:space:]]/s/^\([[:space:]]*[^#]\)/#\1/g' harbor.yml



    # Install Harbor
    ./install.sh || { log error "安装Harbor失败"; exit 1; }

    # 配置并启动服务
    cp harbor.service /etc/systemd/system/ || { log error "复制harbor.service失败"; exit 1; }

    
    # 重新加载 systemd 配置
    systemctl daemon-reload || { log error "重新加载systemd配置失败"; exit 1; }
    systemctl enable harbor || { log error "设置harbor开机自启动失败"; exit 1; }
    systemctl start harbor || { log error "启动harbor服务失败"; exit 1; }

    # Wait for service to be ready
    log info "等待 Harbor 服务启动..."
    local max_retries=30
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if docker ps | grep -q "goharbor/harbor-portal" && \
           docker ps | grep -q "goharbor/harbor-core" && \
           docker ps | grep -q "goharbor/nginx-photon"; then
            sleep 30
            if check_harbor_connectivity; then
                cd "${PKGPWD}"
                log info "Harbor安装完成，访问地址: http://${IP_ADDRESS}:${HARBOR_PORT}"
                return 0
            fi
        fi

        log info "Harbor 服务正在启动中...(${retry_count}/${max_retries})"
        sleep 10
        ((retry_count++))
    done

    log error "Harbor 服务启动超时，请检查服务状态"
    exit 1
}

# 安装Kube-OVN
function install_kube_ovn() {
    log info "安装 Kube-OVN"
    bash "${OTHERS_DIR}/install.sh" || { log error "安装Kube-OVN失败"; exit 1; }
}

# 修改 setup_univirt_inventory 函数
function setup_univirt_inventory() {
    local source_dir="${PKGPWD}"
    local target_dir="${OTHERS_DIR}/uni-virt"
    local inventory_file="inventory.ini"
    
    log info "配置 UniVirt 的 inventory 文件"
    
    # 检查源文件是否存在
    if [ ! -f "${source_dir}/${inventory_file}" ]; then
        log error "源 inventory 文件不存在: ${source_dir}/${inventory_file}"
        exit 1
    fi
    
    # 检查目标目录是否存在
    if [ ! -d "${target_dir}" ]; then
        log error "UniVirt 目录不存在: ${target_dir}"
        exit 1
    fi
    
    # 如果目标文件存在，直接删除
    if [ -f "${target_dir}/${inventory_file}" ]; then
        log info "删除已存在的 inventory 文件"
        rm -f "${target_dir}/${inventory_file}" || {
            log error "删除已存在的 inventory 文件失败"
            exit 1
        }
    fi
    
    # 创建临时文件
    local temp_file="${target_dir}/${inventory_file}.tmp"
    
    # 使用当前节点IP更新inventory内容
    {
        # master 部分
        echo "[master] # 主节点组"
        echo "# 填节点hostname，即IP地址"
        echo "${IP_ADDRESS}"
        echo ""
        
        # worker 部分
        echo "[worker] # 计算节点组"
        echo "# 填节点hostname，即IP地址"
        echo "${IP_ADDRESS}"
        echo ""
        
        # chrony 部分
        echo "[chrony] # 时间服务器，只设置1台"
        echo "# 填节点hostname，即IP地址"
        echo "${IP_ADDRESS}"
    } > "$temp_file"
    
    # 检查临时文件是否创建成功
    if [ ! -f "$temp_file" ]; then
        log error "创建临时 inventory 文件失败"
        exit 1
    fi
    
    # 移动临时文件到目标位置
    mv "$temp_file" "${target_dir}/${inventory_file}" || {
        log error "更新 inventory 文件失败"
        rm -f "$temp_file"
        exit 1
    }
    
    # 设置适当的权限
    chmod 644 "${target_dir}/${inventory_file}" || {
        log error "设置 inventory 文件权限失败"
        exit 1
    }
    
    log info "成功更新 UniVirt 的 inventory 文件"
    return 0
}

# 修改 install_uni_virt 函数
function install_uni_virt() {
    log info "检查 Kubernetes 集群状态"
    check_kubernetes_ready
    
    log info "安装 uni-virt"
    cd "${OTHERS_DIR}/uni-virt" || { log error "进入uni-virt目录失败"; exit 1; }

    # 配置 inventory 文件
    setup_univirt_inventory || { log error "配置 inventory 失败"; exit 1; }

    # 获取节点信息（使用配置的IP地址）
    MASTER_NODE="${IP_ADDRESS}"
    WORKER_NODES="${IP_ADDRESS}"

    # 安装步骤
    ansible-playbook -i inventory.ini -e "offline=1" scripts/ansible/playbooks/install_packages_and_dependencies.yml || { log error "安装uni-virt依赖失败"; exit 1; }
    ansible-playbook -i inventory.ini scripts/ansible/playbooks/install_and_setup_chrony.yml || { log error "设置集群时区失败"; exit 1; }
    ansible-playbook -i inventory.ini scripts/ansible/playbooks/label_k8s_nodes.yml || { log error "节点打标签失败"; exit 1; }

    VERSION="v1.0.0.lab"
    bash scripts/shells/release-offline-centos7.sh ${VERSION} || { log error "打镜像失败"; exit 1; }
    ansible-playbook -i localhost -e "ver=${VERSION} offline=1" scripts/ansible/playbooks/install_uniVirt.yml || { log error "安装uni-virt失败"; exit 1; }
    ansible-playbook -i inventory.ini -e "offline=1" scripts/ansible/playbooks/create_comm_service_env.yml || { log error "配置外部服务失败"; exit 1; }

    # 验证安装
    kubectl get po -n kube-system | grep virt-tool || { log error "uni-virt程序未正常运行"; exit 1; }
    cd "${PKGPWD}"
}

# 卸载kubernetes集群
function destroy_kubernetes() {
    log info "开始卸载 Kubernetes 集群"
    
    # 执行 kubez-ansible destroy
    kubez-ansible destroy --yes-i-really-really-mean-it || { log error "卸载 Kubernetes 集群失败"; exit 1; }
    
    # 清理 CNI 配置
    log info "清理 CNI 配置"
    rm -rf /etc/cni/net.d/* || log error "清理 CNI 配置失败"
    
    # 清理网络接口
    log info "清理网络接口"
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    # 清理 IPVS 表
    log info "清理 IPVS 表"
    if command -v ipvsadm >/dev/null 2>&1; then
        ipvsadm --clear || log error "清理 IPVS 表失败"
    fi
    
    # 清理 iptables 规则
    log info "清理 iptables 规则"
    iptables -F || log error "清理 iptables 规则失败"
    iptables -X || log error "删除自定义 iptables 链失败"
    iptables -t nat -F || log error "清理 NAT 表失败"
    iptables -t nat -X || log error "删除自定义 NAT 链失败"
    iptables -t mangle -F || log error "清理 mangle 表失败"
    iptables -t mangle -X || log error "删除自定义 mangle 链失败"
    
    # 清理 kubeconfig
    log info "清理 kubeconfig 文件"
    rm -rf $HOME/.kube/config || log error "清理 kubeconfig 失败"
    rm -rf /etc/kubernetes/* || log error "清理 kubernetes 配置文件失败"
    
    # 停止并禁用相关服务
    log info "停止并禁用相关服务"
    systemctl stop kubelet docker containerd haproxy keepalived 2>/dev/null || true
    systemctl disable kubelet docker containerd haproxy keepalived 2>/dev/null || true
    
    # 清理目录
    log info "清理相关目录"
    rm -rf /var/lib/kubelet/
    rm -rf /var/lib/docker/
    rm -rf /var/lib/containerd/
    rm -rf /var/lib/etcd/
    rm -rf /var/log/pods/
    
    log info "Kubernetes 集群卸载完成"
}

# 显示帮助信息
function show_help() {
    echo "使用方法: $0 <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  install <选项>    安装指定组件"
    echo ""
    echo "安装选项:"
    echo "  all          安装所有组件（完整安装）"
    echo "  harbor      仅安装 Harbor"
    echo "  monitoring  仅安装监控组件（Prometheus + Grafana）"
    echo "  univirt    仅安装 UniVirt"
    echo ""
    echo "其他命令:"
    echo "  destroy      卸载系统"
    echo "  help        显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  HARBOR_PORT  设置Harbor端口 (默认: 8080)"
    echo ""
    echo "示例:"
    echo "  $0 install all                    # 完整安装所有组件"
    echo "  $0 install harbor                # 仅安装 Harbor"
    echo "  HARBOR_PORT=9090 $0 install harbor  # 使用自定义端口安装 Harbor"
}

# 清理旧的配置和数据
function cleanup_old_data() {
    log info "检查并清理旧的配置和数据..."
    
    # 需要清理的目录列表
    local dirs_to_clean=(
        "/data/nexus_local"
        "/data/harbor"
        "/data/registry"
        "/data/database"
        "/data/redis"
        "/data/prometheus"
        "/data/grafana"
        "/data/secret"
        "/var/log/harbor"
    )

    # 检查并清理每个目录
    for dir in "${dirs_to_clean[@]}"; do
        if [ -d "$dir" ]; then
            log info "清理目录: $dir"
            rm -rf "$dir" || { log error "清理 $dir 失败"; exit 1; }
        fi
    done

    # 清理 Harbor 相关配置
    if [ -d "/usr/local/harbor" ]; then
        log info "清理 Harbor 配置目录"
        rm -rf /usr/local/harbor || { log error "清理 Harbor 配置目录失败"; exit 1; }
    fi

    # 停止并清理 Harbor 服务
    if systemctl is-active harbor &>/dev/null; then
        log info "停止 Harbor 服务"
        systemctl stop harbor
        systemctl disable harbor
        rm -f /etc/systemd/system/harbor.service
        systemctl daemon-reload
    fi

    # 清理 Docker 容器和网络
    if command -v docker &>/dev/null; then
        log info "清理 Docker 资源"
        docker ps -a | grep 'harbor' | awk '{print $1}' | xargs -r docker rm -f
        docker network ls | grep 'harbor' | awk '{print $1}' | xargs -r docker network rm
    fi

    log info "旧数据清理完成"
}

# 在主函数中添加调用
function main() {
    case "$1" in
        "install")
            if [ -z "$2" ]; then
                log error "请指定安装选项"
                show_help
                exit 1
            fi
            
            case "$2" in
                "all")
                    log info "开始完整安装..."
                    init_env
                    check_ports_availability
                    cleanup_old_data
                    check_files
                    install_nexus
                    process_materials
                    install_kubez_ansible
                    setup_kubernetes
                    install_kube_ovn
                    wait_kubernetes_ready
                    install_monitoring
                    install_harbor
                    install_uni_virt
                    log info "所有组件安装完成！"
                    kubectl get pods -A
                    ;;
                    
                "harbor")
                    log info "开始安装 Harbor..."
                    init_env
                    check_ports_availability
                    cleanup_old_data
                    install_harbor
                    log info "Harbor 安装完成"
                    ;;
                    
                "monitoring")
                    log info "开始安装监控组件..."
                    init_env
                    # 确保必要目录存在
                    mkdir -p /data/prometheus /data/grafana
                    install_monitoring
                    log info "监控组件安装完成"
                    ;;
                    
                "univirt")
                    log info "开始安装 UniVirt..."
                    init_env
                    install_uni_virt
                    log info "UniVirt 安装完成"
                    ;;
                    
                *)
                    log error "未知的安装选项: $2"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
            
        "destroy")
            init_env
            run_kubez_ansible "destroy" "--yes-i-really-really-mean-it"
            log info "集群已成功卸载"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log error "无效的操作，请使用 'install'、'destroy' 或 'help'"
            show_help
            exit 1
            ;;
    esac
}

# 添加检查依赖的函数
function check_kubernetes_ready() {
    if ! command -v kubectl &> /dev/null; then
        log error "kubectl 未安装，请先安装 Kubernetes"
        exit 1
    fi
    
    if ! kubectl get nodes &> /dev/null; then
        log error "无法连接到 Kubernetes 集群，请确保集群已正常运行"
        exit 1
    fi
    
    log info "Kubernetes 集群检查通过"
    return 0
}

# 添加安装选项验证函数
function validate_install_option() {
    local option="$1"
    local valid_options=("all" "harbor" "monitoring" "univirt")
    
    for valid_option in "${valid_options[@]}"; do
        if [ "$option" = "$valid_option" ]; then
            return 0
        fi
    done
    
    log error "无效的安装选项: $option"
    echo "有效的安装选项包括: ${valid_options[*]}"
    return 1
}

# 在 main 函数调用前添加参数验证
if [ "$1" = "install" ]; then
    if [ -z "$2" ]; then
        log error "请指定安装选项"
        show_help
        exit 1
    fi
    validate_install_option "$2" || exit 1
fi

# 执行主程序
main "$@"
