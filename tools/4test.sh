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
    export INVENTORY="/usr/share/kubez-ansible/ansible/inventory/all-in-one"
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


# 修改检查系统版本的函数
function check_system_version() {
    log info "检查系统版本..."
    
    # 检查是否为 CentOS 系统
    if [ ! -f "/etc/centos-release" ]; then
        log error "当前仅支持 CentOS 系统"
        exit 1
    fi
    
    # 获取完整的系统版本信息
    local full_version=$(cat /etc/centos-release)
    
    # 定义支持的 CentOS 7.x 版本列表
    local supported_versions=(
        "CentOS Linux release 7.9"
        "CentOS Linux release 7.8"
        "CentOS Linux release 7.6"
    )
    
    # 检查是否为支持的版本
    local version_supported=0
    local detected_version=""
    
    for version in "${supported_versions[@]}"; do
        if echo "$full_version" | grep -q "$version"; then
            version_supported=1
            detected_version="$version"
            break
        fi
    done
    
    if [ $version_supported -eq 0 ]; then
        log error "当前系统版本不支持"
        log error "支持的版本包括："
        for version in "${supported_versions[@]}"; do
            log error "  - ${version}"
        done
        log error "检测到系统版本为: ${full_version}"
        exit 1
    fi
    
    # 获取具体的小版本号
    local version_number=$(echo "$full_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    log info "系统版本检查通过: CentOS ${version_number}"
    
    # 检查系统架构
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        log error "当前仅支持 x86_64 架构，检测到系统架构为 ${arch}"
        exit 1
    fi
    log info "系统架构检查通过: ${arch}"
    
    # 检查系统内核版本
    local kernel_version=$(uname -r)
    log info "当前系统内核版本: ${kernel_version}"
    
    # # 检查 SELinux 状态
    # local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
    # if [ "$selinux_status" = "Enforcing" ]; then
    #     log error "请先禁用 SELinux"
    #     exit 1
    # fi
    # log info "SELinux 状态检查通过: ${selinux_status}"
    
    # 根据不同版本输出特定的警告或建议
    case "$detected_version" in
        "CentOS Linux release 7.9")
#            log info "检测到最新的 CentOS 7.9 版本，推荐使用此版本"
            ;;
        "CentOS Linux release 7.8")
#            log info "警告: CentOS 7.8 版本可能存在已知安全漏洞，建议升级到 7.9"
            ;;
        "CentOS Linux release 7.6")
#            log info "警告: CentOS 7.6 版本过旧，强烈建议升级到 7.9"
            ;;
    esac
    
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
    # 添加 UniVirt 版本环境变量，允许用户自定义，默认为v1.0.0.lab
    export UNIVIRT_VERSION=${UNIVIRT_VERSION:-"v1.0.0.lab"}
    
    # 检查Harbor端口是否为禁用端口
    if [ "$HARBOR_PORT" = "58000" ] || [ "$HARBOR_PORT" = "58001" ]; then
        log error "Harbor端口不能设置为58000或58001，这些端口已被系统保留"
        exit 1
    fi
    # 输出所有的配置参数
    
    export LOCAL_REGISTRY="${IP_ADDRESS}:58001/pixiuio"
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
    local service_name=$2
    local timeout=1  # 设置超时时间为1秒
    
    log info "检查端口 ${port} 是否被占用..."
    
    # 使用 ss 命令检查端口占用
    if ss -Hln "sport = :${port}" | grep -q ":${port}"; then
        # 特殊处理 Nexus 端口 (58000, 58001)
        if [ "$port" = "58000" ] || [ "$port" = "58001" ]; then
            if systemctl is-active nexus &>/dev/null; then
                log info "端口 ${port} 被 Nexus 服务占用，这是预期的行为"
                return 0
            elif pgrep -f "nexus" >/dev/null; then
                log info "端口 ${port} 被 Nexus 进程占用，这是预期的行为"
                return 0
            fi
        fi
        
        # 特殊处理 Harbor 端口
        if [ "$port" = "${HARBOR_PORT}" ]; then
            if systemctl is-active harbor &>/dev/null; then
                log info "端口 ${port} 被 Harbor 服务占用，这是预期的行为"
                return 0
            elif docker ps | grep -q "goharbor/nginx-photon"; then
                log info "端口 ${port} 被 Harbor 容器占用，这是预期的行为"
                return 0
            fi
        fi
        
        log error "端口 ${port} 已被其他服务占用"
        return 1
    fi
    
    # 使用 /dev/tcp 进行双重检查
    if timeout ${timeout} bash -c "</dev/tcp/127.0.0.1/${port}" &>/dev/null; then
        # 再次进行 Nexus 和 Harbor 的特殊处理
        if [ "$port" = "58000" ] || [ "$port" = "58001" ]; then
            if systemctl is-active nexus &>/dev/null || pgrep -f "nexus" >/dev/null; then
                log info "端口 ${port} 被 Nexus 服务占用，这是预期的行为"
                return 0
            fi
        elif [ "$port" = "${HARBOR_PORT}" ]; then
            if systemctl is-active harbor &>/dev/null || docker ps | grep -q "goharbor/nginx-photon"; then
                log info "端口 ${port} 被 Harbor 服务占用，这是预期的行为"
                return 0
            fi
        fi
        
        log error "端口 ${port} 已被其他服务占用"
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
        if ! check_port_usage "${port}" "${ports[$port]}"; then
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

# 添加检查 Harbor 相关文件的专门函数
function check_harbor_files() {
    log info "检查 Harbor 相关文件..."
    
    # 检查必要的 Harbor 文件
    local harbor_files=(
        "${OTHERS_DIR}/harbor/harbor.yml"
        "${OTHERS_DIR}/harbor/install.sh"
        "${OTHERS_DIR}/harbor/harbor.service"
        "${OTHERS_DIR}/harbor/common.sh"
        "${OTHERS_DIR}/harbor/prepare"
    )

    # 检查 others 目录是否存在，如果不存在则解压
    if [ ! -d "${OTHERS_DIR}" ]; then
        log info "解压 others.tar.gz..."
        tar -zxvf "${BASE_FILES_DIR}/others.tar.gz" || { 
            log error "解压 others.tar.gz 失败"
            exit 1
        }
    fi

    # 检查 harbor 目录是否存在
    if [ ! -d "${OTHERS_DIR}/harbor" ]; then
        log error "Harbor 目录不存在: ${OTHERS_DIR}/harbor"
        exit 1
    fi

    # 检查每个必要文件
    for file in "${harbor_files[@]}"; do
        if [ ! -f "$file" ]; then
            log error "必要的 Harbor 文件不存在: $(basename ${file})"
            exit 1
        fi
    done

    log info "Harbor 文件检查完成"
    return 0
}

# 修改原有的 check_files 函数
function check_files() {
    local check_all=$1  # 传入参数，true 表示检查所有文件，false 表示只检查 Harbor 相关文件
    
    if [ "$check_all" = true ]; then
        log info "检查所有必要文件..."
        
        # 定义所有可能需要的文件
        local all_required_files=(
            "${BASE_FILES_DIR}/k8s-centos7-v${KUBE_VERSION}_images.tar.gz"
            "${BASE_FILES_DIR}/k8s-centos7-v${KUBE_VERSION}-rpm.tar.gz"
            "${BASE_FILES_DIR}/kubez-ansible-offline-master.zip"
            "${BASE_FILES_DIR}/nexus.tar.gz"
            "${BASE_FILES_DIR}/others.tar.gz"
            "${BASE_FILES_DIR}/image.tar.gz"
        )
        
        # 检查所有必要文件是否存在
        for file in "${all_required_files[@]}"; do
            if [ ! -f "$file" ]; then
                log error "必要文件不存在: $(basename ${file})"
                exit 1
            fi
        done

        # 检查目录状态
        log info "检查目录..."
        local current_items=(${PKGPWD}/*)
        local illegal_items=()
        
        for current_item in "${current_items[@]}"; do
            # 跳过当前脚本文件
            if [ "$(basename ${current_item})" = "$(basename $0)" ]; then
                continue
            fi
            
            # 检查是否为目录 - 完整安装时所有目录都是非法的
            if [ -d "${current_item}" ]; then
                illegal_items+=("目录: $(basename ${current_item})")
                continue
            fi
            
            # 检查文件是否在允许列表中
            local is_allowed_file=false
            for allowed_file in "${all_required_files[@]}"; do
                if [ "${current_item}" = "${allowed_file}" ]; then
                    is_allowed_file=true
                    break
                fi
            done
            
            if [ "$is_allowed_file" = false ]; then
                illegal_items+=("文件: $(basename ${current_item})")
            fi
        done
        
        # 处理非法项目
        if [ ${#illegal_items[@]} -gt 0 ]; then
            log error "发现以下非法项目:"
            for illegal_item in "${illegal_items[@]}"; do
                log error "  - ${illegal_item}"
            done
            log error "完整安装时目录必须只包含必要的压缩包文件"
            exit 1
        fi
    else
        log info "检查 Harbor 相关文件..."
        
        # 只检查 others 目录或 others.tar.gz 是否存在
        if [ ! -d "${OTHERS_DIR}" ]; then
            if [ ! -f "${BASE_FILES_DIR}/others.tar.gz" ]; then
                log error "未找到 others 目录或 others.tar.gz"
                exit 1
            fi
            
            # 解压 others.tar.gz
            log info "解压 others.tar.gz..."
            tar -zxvf "${BASE_FILES_DIR}/others.tar.gz" || { 
                log error "解压 others.tar.gz 失败"
                exit 1
            }
        fi
    fi

    # 检查 Harbor 相关文件
    local harbor_files=(
        "${OTHERS_DIR}/harbor/harbor.yml"
        "${OTHERS_DIR}/harbor/install.sh"
        "${OTHERS_DIR}/harbor/harbor.service"
        "${OTHERS_DIR}/harbor/common.sh"
        "${OTHERS_DIR}/harbor/prepare"
    )

    # 检查 harbor 目录是否存在
    if [ ! -d "${OTHERS_DIR}/harbor" ]; then
        log error "Harbor 目录不存在: ${OTHERS_DIR}/harbor"
        exit 1
    fi

    # 检查每个 Harbor 必要文件
    for file in "${harbor_files[@]}"; do
        if [ ! -f "$file" ]; then
            log error "必要的 Harbor 文件不存在: $(basename ${file})"
            exit 1
        fi
    done

    if [ "$check_all" = true ]; then
        log info "所有文件检查完成"
    else
        log info "Harbor 文件检查完成"
    fi
    return 0
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

# 添加检查并安装 unzip 的函数
function ensure_unzip_installed() {
    log info "检查 unzip 是否已安装..."
    
    # 检查 unzip 命令是否存在
    if ! command -v unzip &>/dev/null; then
        log info "unzip 未安装，开始安装..."
        
        # 尝试使用 yum 安装 unzip
        if ! yum install -y unzip; then
            log error "安装 unzip 失败，请检查 YUM 源配置"
            exit 1
        fi
        
        # 再次检查安装是否成功
        if ! command -v unzip &>/dev/null; then
            log error "unzip 安装失败，请手动检查安装状态"
            exit 1
        fi
        
        log info "unzip 安装成功"
    else
        log info "unzip 已安装"
    fi
}

# 修改 install_kubez_ansible 函数，添加 unzip 检查
function install_kubez_ansible() {
    cd ${PKGPWD}
    
    # 在解压前确保 unzip 已安装
    ensure_unzip_installed
    
    if [ ! -d "kubez-ansible-offline-master" ]; then
        log info "解压kubez-ansible-offline-master.zip"
        if ! unzip -o kubez-ansible-offline-master.zip; then
            log error "解压kubez-ansible-offline-master.zip失败"
            exit 1
        fi
    fi

    # 安装基础包
    if ! yum -y install ansible python2-pip; then
        log error "安装基础包失败"
        exit 1
    fi
    
    cd kubez-ansible-offline-master
    if ! pip install pip/pbr-5.11.1-py2.py3-none-any.whl; then
        log error "安装pbr失败"
        exit 1
    fi
    
    cp tools/git /usr/local/bin && chmod 755 /usr/local/bin/git && git init
    
    # 安装 kubez-ansible
    if ! python setup.py install; then
        log error "安装kubez-ansible失败"
        exit 1
    fi
    
    cp -rf etc/kubez/ /etc/kubez
    cd ${PKGPWD}

    # 配置免密登录
    setup_kubez_ansible_auth
}

# 添加检查和重置 Kubernetes 的函数
function check_and_reset_kubernetes() {
    log info "检查是否存在旧的 Kubernetes 配置..."
    
    # 检查 kubeadm 命令是否存在
    if command -v kubeadm &>/dev/null; then
        # 检查是否存在 Kubernetes 配置文件
        if [ -f "/etc/kubernetes/admin.conf" ] || [ -d "/etc/kubernetes/manifests" ]; then
            log info "检测到已有的 Kubernetes 配置，执行重置操作..."
            
            # 停止所有 Kubernetes 相关的容器
            if command -v crictl &>/dev/null; then
                log info "停止所有 Kubernetes 容器..."
                crictl pods -q | xargs -r crictl stopp 2>/dev/null || true
                crictl pods -q | xargs -r crictl rmp 2>/dev/null || true
            fi
            
            # 执行 kubeadm reset
            log info "执行 kubeadm reset..."
            kubeadm reset -f || {
                log error "kubeadm reset 执行失败"
                exit 1
            }
            
            # 清理额外的配置文件和目录
            log info "清理 Kubernetes 配置文件和目录..."
            rm -rf /etc/kubernetes/* || true
            rm -rf /var/lib/kubelet/* || true
            rm -rf /var/lib/etcd/* || true
            rm -rf $HOME/.kube/config || true
            
            # 清理网络配置
            log info "清理网络配置..."
            ip link delete cni0 2>/dev/null || true
            ip link delete flannel.1 2>/dev/null || true
            
            # 清理 iptables 规则
            log info "清理 iptables 规则..."
            iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
            
            log info "Kubernetes 重置完成"
        else
            log info "未检测到现有的 Kubernetes 配置，无需重置"
        fi
    else
        log info "未检测到 kubeadm 命令，无需重置"
    fi
}

# 添加更新 inventory 的函数
function update_inventory() {
    log info "更新 inventory 配置..."
    
    local inventory_file="${INVENTORY}"
    
    # 检查文件是否存在
    if [ ! -f "${inventory_file}" ]; then
        log error "inventory 文件不存在: ${inventory_file}"
        exit 1
    fi
    
    # 创建临时文件
    local temp_file="${inventory_file}.tmp"
    
    # 生成新的 inventory 内容
    {
        echo "[docker-master]"
        echo "localhost       ansible_connection=local"
        echo ""
        echo "[docker-node]"
        echo "localhost       ansible_connection=local"
        echo ""
        echo "[containerd-master]"
        echo ""
        echo "[containerd-node]"
        echo ""
        echo "[kube-master:children]"
        echo "docker-master"
        echo "containerd-master"
        echo ""
        echo "[kube-node:children]"
        echo "docker-node"
        echo "containerd-node"
        echo ""
        echo "[storage]"
        echo "localhost       ansible_connection=local"
        echo ""
        echo "[baremetal:children]"
        echo "kube-master"
        echo "kube-node"
        echo "storage"
        echo ""
        echo "[kubernetes:children]"
        echo "kube-master"
        echo "kube-node"
        echo ""
        echo "[nfs-server:children]"
        echo "storage"
        echo ""
        echo "[haproxy:children]"
        echo "kube-master"
    } > "$temp_file"
    
    # 检查临时文件是否创建成功
    if [ ! -f "$temp_file" ]; then
        log error "创建临时 inventory 文件失败"
        exit 1
    fi
    
    # 备份原文件
    local backup_file="${inventory_file}.bak.$(date +%Y%m%d_%H%M%S)"
    if ! cp "${inventory_file}" "${backup_file}"; then
        log error "备份原 inventory 文件失败"
        rm -f "$temp_file"
        exit 1
    fi
    
    # 替换原文件
    if ! mv "$temp_file" "${inventory_file}"; then
        log error "更新 inventory 文件失败"
        rm -f "$temp_file"
        exit 1
    fi
    
    # 设置适当的权限
    chmod 644 "${inventory_file}" || {
        log error "设置 inventory 文件权限失败"
        exit 1
    }
    
    log info "inventory 配置更新成功"
    return 0
}

# 修改 setup_kubernetes 函数，添加重置检查和更新 inventory
function setup_kubernetes() {
    # 首先检查并重置已有的 Kubernetes 配置
    check_and_reset_kubernetes
    
    # 更新 inventory 配置
    update_inventory || { log error "更新 inventory 配置失败"; exit 1; }
    
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
    sed -i "s|yum_baseurl: .*|yum_baseurl: \"${YUM_REPO}\"|g" /etc/kubez/globals.yml
    sed -i "s|image_repository: .*|image_repository: \"${LOCAL_REGISTRY}\"|g" /etc/kubez/globals.yml
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

# 添加安装 docker-compose 的函数
function install_docker_compose() {
    log info "检查并安装 docker-compose..."
    
    # 检查 docker-compose 是否已安装
    if command -v docker-compose &>/dev/null; then
        local current_version=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        log info "docker-compose 已安装，版本: ${current_version}"
        return 0
    fi
    
    # 安装 docker-compose
    log info "开始安装 docker-compose..."
    
    # 使用 yum 安装
    if ! yum install -y docker-compose; then
        log error "通过 yum 安装 docker-compose 失败"
        exit 1
    fi
    
    # 验证安装
    if ! command -v docker-compose &>/dev/null; then
        log error "docker-compose 安装失败"
        exit 1
    fi
    
    local installed_version=$(docker-compose --version | awk '{print $3}' | tr -d ',')
    log info "docker-compose 安装成功，版本: ${installed_version}"
    return 0
}

# 添加清理 Harbor 数据的专门函数
function cleanup_harbor_data() {
    log info "清理 Harbor 相关数据..."
    
    # 停止 Harbor 服务
    if systemctl is-active harbor &>/dev/null; then
        log info "停止 Harbor 服务"
        systemctl stop harbor
        systemctl disable harbor
        rm -f /etc/systemd/system/harbor.service
        systemctl daemon-reload
    fi

    # 清理 Harbor 容器和镜像
    if command -v docker &>/dev/null; then
        log info "清理 Harbor 相关容器"
        # 停止并删除所有 goharbor 容器
        docker ps -a | grep 'goharbor' | awk '{print $1}' | xargs -r docker rm -f
        
        # 删除 Harbor 相关网络
        docker network ls | grep 'harbor' | awk '{print $1}' | xargs -r docker network rm
    fi

    # 需要清理的 Harbor 相关目录
    local harbor_dirs=(
        "/data/harbor"
        "/data/registry"
        "/data/database"
        "/data/redis"
        "/data/secret"
        "/var/log/harbor"
        "/usr/local/harbor"
    )

    # 清理 Harbor 相关目录
    for dir in "${harbor_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log info "清理目录: $dir"
            rm -rf "$dir" || log error "清理 $dir 失败，继续处理其他目录"
        fi
    done

    log info "Harbor 数据清理完成"
}

# 修改 install_harbor 函数，在开始时调用清理函数
function install_harbor() {
    log info "安装 Harbor"
    
    # 首先安装 docker-compose
    install_docker_compose || { log error "安装 docker-compose 失败"; exit 1; }
    
    # 清理旧的 Harbor 数据
    cleanup_harbor_data || { log error "清理 Harbor 数据失败"; exit 1; }
    
    cd "${OTHERS_DIR}/harbor" || { log error "进入harbor目录失败"; exit 1; }

    # 创建必要的目录
    mkdir -p /var/log/harbor /data/registry /data/database /data/redis || { log error "创建必要目录失败"; exit 1; }
    chmod 755 /var/log/harbor /data/registry /data/database /data/redis
    chown -R 10000:10000 /data/

    # 先复制整个目录到 /usr/local
    log info "复制 Harbor 目录到 /usr/local"
    cp -r "${OTHERS_DIR}/harbor" /usr/local/ || { log error "复制harbor目录失败"; exit 1; }
    
    # 进入目标目录进行配置
    cd /usr/local/harbor || { log error "进入/usr/local/harbor目录失败"; exit 1; }
    
    # 配置 harbor.yml
    log info "配置 harbor.yml"
    if [ -f "harbor.yml" ]; then
        # 备份原配置文件
        cp -f harbor.yml "harbor.yml.bak.$(date +%Y%m%d_%H%M%S)" || log info "无需备份原配置文件"
    else
        # 如果不存在则从模板创建
        cp -f harbor.yml.tmpl harbor.yml || { log error "创建harbor.yml失败"; exit 1; }
    fi

    # 修改配置文件
    log info "更新 harbor.yml 配置..."
    
    # 修改 hostname
    sed -i "s/^hostname: .*/hostname: ${IP_ADDRESS}/" harbor.yml || {
        log error "修改 hostname 失败"
        exit 1
    }
    
    # 修改端口
    sed -i "/^http:/,/^[^[:space:]]/{s/port: .*/port: ${HARBOR_PORT}/}" harbor.yml || {
        log error "修改端口失败"
        exit 1
    }
    
    # 注释掉 https 部分
    sed -i '/^https:/,/^[^[:space:]]/s/^[[:space:]]*[^#]/#&/' harbor.yml || {
        log error "注释 https 配置失败"
        exit 1
    }

    # 安装 Harbor
    log info "开始安装 Harbor..."
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

# 添加获取 hostname 的辅助函数
function get_node_hostname() {
    local ip="$1"
    local hostname
    
    # 尝试获取 hostname
    hostname=$(hostname)
    
    # 检查获取到的 hostname 是否有效
    if [ -n "$hostname" ]; then
        echo "$hostname"
        return 0
    fi
    
    # 如果没有有效的 hostname，返回 IP 地址
    echo "$ip"
    return 0
}

# 添加一个辅助函数来查找 UniVirt 目录
function find_univirt_dir() {
    local base_dir="$1"
    local possible_names=("uniVirt" "uni-virt" "univirt")
    
    for name in "${possible_names[@]}"; do
        if [ -d "${base_dir}/${name}" ]; then
            echo "${base_dir}/${name}"
            return 0
        fi
    done
    
    # 如果都没找到，返回默认名称（用于错误消息）
    echo "${base_dir}/uni-virt"
    return 1
}

# 修改 setup_univirt_inventory 函数
function setup_univirt_inventory() {
    local univirt_dir=$(find_univirt_dir "${OTHERS_DIR}")
    local inventory_file="inventory.ini"
    local full_path="${univirt_dir}/${inventory_file}"
    
    if [ ! -d "${univirt_dir}" ]; then
        log error "UniVirt 目录不存在: ${univirt_dir}"
        exit 1
    fi
    
    log info "配置 UniVirt 的 inventory 文件: ${full_path}"
    
    # 获取节点标识（hostname 或 IP）
    local node_identifier=$(get_node_hostname "${IP_ADDRESS}")
    log info "使用节点标识: ${node_identifier}"
    
    # 如果目标文件存在，创建备份
    if [ -f "${full_path}" ]; then
        local backup_file="${full_path}.bak.$(date +%Y%m%d_%H%M%S)"
        log info "创建现有 inventory 文件的备份: ${backup_file}"
        cp -f "${full_path}" "${backup_file}" || {
            log error "备份现有 inventory 文件失败"
            exit 1
        }
    fi
    
    # 创建临时文件
    local temp_file="${full_path}.tmp"
    
    # 使用节点标识更新 inventory 内容
    {
        # master 部分
        echo "[master] # 主节点组"
        echo "# 填节点hostname，即IP地址"
        echo "${node_identifier}"
        echo ""
        
        # worker 部分
        echo "[worker] # 计算节点组"
        echo "# 填节点hostname，即IP地址"
        echo "${node_identifier}"
        echo ""
        
        # chrony 部分
        echo "[chrony] # 时间服务器，只设置1台"
        echo "# 填节点hostname，即IP地址"
        echo "${node_identifier}"
    } > "$temp_file"
    
    # 检查临时文件是否创建成功
    if [ ! -f "$temp_file" ]; then
        log error "创建临时 inventory 文件失败"
        exit 1
    fi
    
    # 移动临时文件到目标位置
    mv "$temp_file" "${full_path}" || {
        log error "更新 inventory 文件失败"
        rm -f "$temp_file"
        exit 1
    }
    
    # 设置适当的权限
    chmod 644 "${full_path}" || {
        log error "设置 inventory 文件权限失败"
        exit 1
    }
    
    log info "成功更新 UniVirt 的 inventory 文件: ${full_path}"
    if [ "${node_identifier}" != "${IP_ADDRESS}" ]; then
        log info "使用 hostname: ${node_identifier} 替代 IP: ${IP_ADDRESS}"
    else
        log info "未找到有效的 hostname，使用 IP 地址: ${IP_ADDRESS}"
    fi
    
    return 0
}

# 修改 install_uni_virt 函数
function install_uni_virt() {
    log info "检查 Kubernetes 集群状态"
    check_kubernetes_ready
    
    local univirt_dir=$(find_univirt_dir "${OTHERS_DIR}")
    if [ ! -d "${univirt_dir}" ]; then
        log error "UniVirt 目录不存在: ${univirt_dir}"
        exit 1
    fi
    
    log info "安装 UniVirt，版本: ${UNIVIRT_VERSION}"
    cd "${univirt_dir}" || { log error "进入 UniVirt 目录失败"; exit 1; }

    # 配置 inventory 文件
    setup_univirt_inventory || { log error "配置 inventory 失败"; exit 1; }

    # 获取节点信息（使用配置的IP地址）
    MASTER_NODE="${IP_ADDRESS}"
    WORKER_NODES="${IP_ADDRESS}"

    # 安装步骤
    ansible-playbook -i inventory.ini -e "offline=1" scripts/ansible/playbooks/install_packages_and_dependencies.yml || { 
        log error "安装uni-virt依赖失败"; 
        exit 1; 
    }
    
    ansible-playbook -i inventory.ini scripts/ansible/playbooks/install_and_setup_chrony.yml || { 
        log error "设置集群时区失败"; 
        exit 1; 
    }
    
    # 检查并删除已存在的标签
    log info "检查并更新节点标签..."
    local node_name=$(kubectl get nodes -o name | head -n 1)
    if [ -n "$node_name" ]; then
        # 尝试删除已存在的标签
        kubectl label node ${node_name#node/} doslab/virt.tool.centos- --overwrite=true || true
        # 重新添加标签
        kubectl label node ${node_name#node/} doslab/virt.tool.centos="" --overwrite=true || {
            log error "更新节点标签失败"
            exit 1
        }
    else
        log error "未找到可用的节点"
        exit 1
    fi

    # 使用环境变量中的版本
    log info "打包镜像，使用版本: ${UNIVIRT_VERSION}"
    bash scripts/shells/release-offline-centos7.sh ${UNIVIRT_VERSION} || { 
        log error "打镜像失败"; 
        exit 1; 
    }
    
    ansible-playbook -i localhost -e "ver=${UNIVIRT_VERSION} offline=1" scripts/ansible/playbooks/install_uniVirt.yml || { 
        log error "安装 UniVirt 失败"; 
        exit 1; 
    }
    
    ansible-playbook -i inventory.ini -e "offline=1" scripts/ansible/playbooks/create_comm_service_env.yml || { 
        log error "配置外部服务失败"; 
        exit 1; 
    }

    # 验证安装
    kubectl get po -n kube-system | grep virt-tool || { 
        log error "uni-virt程序未正常运行"; 
        exit 1; 
    }
    
    log info "uni-virt ${UNIVIRT_VERSION} 安装完成"
    cd "${PKGPWD}"
}

# 卸载kubernetes集群
function destroy_kubernetes() {
    log info "开始卸载 Kubernetes 集群"
    
    # 执行 kubez-ansible destroy
    kubez-ansible destroy --yes-i-really-really-mean-it || { 
        log error "卸载 Kubernetes 集群失败"; 
        exit 1; 
    }
    
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
    echo "  HARBOR_PORT      设置Harbor端口 (默认: 8080)"
    echo "  UNIVIRT_VERSION  设置UniVirt版本 (默认: v1.0.0.lab)"
    echo ""
    echo "示例:"
    echo "  $0 install all                                  # 完整安装所有组件"
    echo "  $0 install harbor                              # 仅安装 Harbor"
    echo "  HARBOR_PORT=9090 $0 install harbor            # 使用自定义端口安装 Harbor"
    echo "  UNIVIRT_VERSION=v2.0.0 $0 install univirt    # 安装指定版本的 UniVirt"
}

# 清理旧的配置和数据
function cleanup_old_data() {
    log info "检查并清理旧的配置和数据..."
    
    # 需要清理的非 Harbor 相关目录
    local dirs_to_clean=(
        "/data/nexus_local"
        "/data/prometheus"
        "/data/grafana"
    )

    # 检查并清理每个目录
    for dir in "${dirs_to_clean[@]}"; do
        if [ -d "$dir" ]; then
            log info "清理目录: $dir"
            rm -rf "$dir" || { log error "清理 $dir 失败"; exit 1; }
        fi
    done

    log info "旧数据清理完成"
}

# 添加检查 Docker 运行状态的函数
function check_docker_running() {
    log info "检查 Docker 运行状态..."
    
    # 检查 docker 命令是否存在
    if ! command -v docker &>/dev/null; then
        log error "Docker 未安装"
        return 1
    fi
    
    # 检查 Docker 守护进程是否运行
    if ! systemctl is-active docker &>/dev/null; then
        log error "Docker 服务未运行"
        return 1
    fi

    # 验证 Docker 是否可用
    if ! docker info &>/dev/null; then
        log error "Docker 服务无法正常通信"
        return 1
    fi

    log info "Docker 运行正常"
    return 0
}

# 添加检查 Ansible 的函数
function check_ansible_installed() {
    log info "检查 Ansible 是否已安装..."
    
    if ! command -v ansible &>/dev/null; then
        log error "Ansible 未安装"
        return 1
    fi
    
    if ! command -v ansible-playbook &>/dev/null; then
        log error "ansible-playbook 命令未找到"
        return 1
    fi

    log info "Ansible 已安装"
    return 0
}

# 添加检查集群通信的函数
function check_cluster_communication() {
    log info "检查集群通信状态..."
    
    # 检查 kubectl 命令
    if ! command -v kubectl &>/dev/null; then
        log error "kubectl 未安装"
        return 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &>/dev/null; then
        log error "无法连接到 Kubernetes 集群"
        return 1
    fi
    
    # 检查节点状态
    if ! kubectl get nodes &>/dev/null; then
        log error "无法获取集群节点信息"
        return 1
    fi
    
    # 检查所有节点是否就绪
    local not_ready_nodes=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [ "$not_ready_nodes" -gt 0 ]; then
        log error "存在未就绪的节点"
        kubectl get nodes
        return 1
    fi

    log info "集群通信正常"
    return 0
}

# 添加综合检查函数
function check_prerequisites() {
    local check_type="$1"
    local check_failed=0
    
    case "$check_type" in
        "harbor")
            log info "执行 Harbor 安装前检查..."
            if ! check_docker_running; then
                check_failed=1
            fi
            ;;
            
        "univirt"|"monitoring")
            log info "执行 ${check_type} 安装前检查..."
            if ! check_docker_running; then
                check_failed=1
            fi
            if ! check_ansible_installed; then
                check_failed=1
            fi
            if ! check_cluster_communication; then
                check_failed=1
            fi
            ;;
            
        *)
            log error "未知的检查类型: ${check_type}"
            return 1
            ;;
    esac
    
    if [ $check_failed -eq 1 ]; then
        log error "${check_type} 安装前检查失败"
        return 1
    fi
    
    log info "${check_type} 安装前检查通过"
    return 0
}

# 修改 main 函数中的安装分支
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
                    check_files true     # 检查所有文件
                    cleanup_old_data
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
                    check_prerequisites "harbor" || { log error "Harbor 安装前检查失败"; exit 1; }
                    check_ports_availability
                    check_files false    # 只检查 Harbor 相关文件
                    install_harbor
                    log info "Harbor 安装完成"
                    ;;
                    
                "monitoring")
                    log info "开始安装监控组件..."
                    init_env
                    check_prerequisites "monitoring" || { log error "监控组件安装前检查失败"; exit 1; }
                    mkdir -p /data/prometheus /data/grafana
                    install_monitoring
                    log info "监控组件安装完成"
                    ;;
                    
                "univirt")
                    log info "开始安装 UniVirt..."
                    init_env
                    check_prerequisites "univirt" || { log error "UniVirt 安装前检查失败"; exit 1; }
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
            # init_env
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
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
