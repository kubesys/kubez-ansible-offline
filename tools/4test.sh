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
export KUBEZ_ANSIBLE_CMD="kubez-ansible"

# 设置 INVENTORY 变量
if [ -z "${INVENTORY}" ]; then
    export INVENTORY="/usr/share/kubez-ansible/ansible/inventory/all-in-one"
fi

# 从 base.sh 获取一些有用的变量
[ -z "${LOCALIP}" ] && LOCALIP=${IP_ADDRESS}
[ -z "${IMAGETAG}" ] && IMAGETAG=${KUBE_VERSION}

# Volcano 监控组件配置变量
export VOLCANO_MONITORING_NAMESPACE="volcano-monitoring"  # 可以在这里修改命名空间
export VOLCANO_MONITORING_IMAGE_PULL_POLICY="IfNotPresent"
export VOLCANO_MONITORING_YAML_FILE="volcano-monitoring-latest.yaml"
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
        "warning")
            echo -e "${timestamp} [${file_name}:${line_number}] \e[33m[ WARNING ]\e[0m $2"
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
    # 由于 bc 命令可能未安装，使用 awk 替代计算内存大小
    mem_total_gb=$(echo "$mem_total_kb" | awk '{printf "%.2f", $1 / 1024 / 1024}')
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
        
        # 检查nexus.sh文件是否存在
        if [ ! -f "/data/nexus_local/nexus.sh" ]; then
            log warn "Nexus 目录存在但 nexus.sh 文件不存在，可能是不完整安装"
            log info "清理现有 Nexus 目录内容并重新安装"
            rm -rf /data/nexus_local/* 2>/dev/null || log error "清理 /data/nexus_local 内容失败，但将继续执行"
            
            # 重新解压安装
            log info "准备重新安装 Nexus"
            tar -zxvf nexus.tar.gz -C /data || { 
                log error "解压nexus.tar.gz失败"
                return 1  # 使用return而不是exit，允许脚本继续执行
            }
        fi
    else
        log info "准备开始安装 Nexus"
        mkdir -p /data
        tar -zxvf nexus.tar.gz -C /data || { 
            log error "解压nexus.tar.gz失败"
            return 1  # 使用return而不是exit，允许脚本继续执行
        }
    fi

    # 检查nexus.sh文件是否存在
    if [ ! -f "/data/nexus_local/nexus.sh" ]; then
        log error "nexus.sh 文件不存在，无法启动 Nexus 服务"
        return 1  # 使用return而不是exit，允许脚本继续执行
    fi

    cd /data/nexus_local && bash nexus.sh start || { 
        log error "启动nexus服务失败"
        return 1  # 使用return而不是exit，允许脚本继续执行
    }

    if ! grep -q "bash nexus.sh start" /etc/rc.d/rc.local; then
        chmod +x /etc/rc.d/rc.local
        echo 'cd /data/nexus_local && bash nexus.sh start' >> /etc/rc.d/rc.local
    fi

    # 等待 Nexus 服务启动
    wait_nexus_ready || return 1  # 允许失败时继续执行
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
    ${KUBEZ_ANSIBLE_CMD} authorized-key || { log error "配置免密登录失败"; exit 1; }

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
            
            # 调用 destroy_kubernetes 函数进行清理
            destroy_kubernetes || {
                log error "Kubernetes 重置失败"
                exit 1
            }
            
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
    
    # 使用 get_node_hostname 函数获取节点标识
    local node_identifier=$(get_node_hostname "${IP_ADDRESS}")
    
    # 创建临时文件
    local temp_file="${inventory_file}.tmp"
    
    # 生成新的 inventory 内容
    {
        echo "[docker-master]"
        echo "${node_identifier}       ansible_connection=local"
        echo ""
        echo "[docker-node]"
        echo "${node_identifier}       ansible_connection=local"
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
        echo "${node_identifier}       ansible_connection=local"
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
# 处理 globals.yml 配置
function setup_globals_config() {
    log info "配置 globals.yml..."

    # 检查并创建配置目录
    mkdir -p /etc/kubez || { log error "创建 /etc/kubez 目录失败"; exit 1; }

    # 检查并备份现有的 globals.yml
    if [ -f "/etc/kubez/globals.yml" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        cp -f /etc/kubez/globals.yml "/etc/kubez/globals.yml.bak.${timestamp}" || {
            log error "备份 globals.yml 失败"
            exit 1
        }
    fi

    # 复制新的配置文件
    cp -f "${PKGPWD}/kubez-ansible-offline-master/etc/kubez/globals.yml" /etc/kubez/globals.yml || {
        log error "复制新的 globals.yml 失败"
        exit 1
    }

    # 基础配置修改
    sed -i "s/kube_release: .*/kube_release: ${KUBE_VERSION}/g" /etc/kubez/globals.yml
    sed -i "s/network_interface: .*/network_interface: \"${NETWORK_INTERFACE}\"/g" /etc/kubez/globals.yml
    sed -i "s|yum_baseurl: .*|yum_baseurl: \"${YUM_REPO}\"|g" /etc/kubez/globals.yml
    sed -i "s|image_repository: .*|image_repository: \"${LOCAL_REGISTRY}\"|g" /etc/kubez/globals.yml
    sed -i "s|image_repository_container: .*|image_repository_container: \"${CONTAINER_REGISTRY}\"|g" /etc/kubez/globals.yml
    sed -i "s/cluster_cidr: .*/cluster_cidr: \"172.30.0.0\/16\"/g" /etc/kubez/globals.yml
    sed -i "s/service_cidr: .*/service_cidr: \"10.254.0.0\/16\"/g" /etc/kubez/globals.yml

    # 如果存在节点配置文件，检查是否需要配置高可用
    if [ -f "${NODE_CONFIG_FILE}" ]; then
        # 获取docker-master节点数量
        local master_count=$(awk '/^\[docker-master\]/{flag=1;next} /^\[/{flag=0} flag&&/^[^#]/{count++} END{print count}' "${NODE_CONFIG_FILE}")

        # 仅当 master 节点大于等于3且为奇数时，启用高可用配置
        if [ $master_count -ge 3 ] && [ $((master_count % 2)) -eq 1 ]; then
            log info "检测到 ${master_count} 个 master 节点，启用高可用配置"

            # 查找可用的 VIP 地址
#            local network_prefix=$(ip -o -4 addr show ${NETWORK_INTERFACE} | awk '{print $4}' | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
#            local vip_found=0

            # 在当前网段中查找未使用的IP作为VIP
#            for i in {2..254}; do
#                local test_ip="${network_prefix}.${i}"
#                if ! ping -c 1 -W 1 "${test_ip}" &>/dev/null; then
#                    log info "找到可用的 VIP 地址: ${test_ip}"
#                    # 启用高可用配置
#                    sed -i "s/^#enable_kubernetes_ha: .*/enable_kubernetes_ha: \"yes\"/" /etc/kubez/globals.yml
#                    sed -i "s/^#kube_vip_address: .*/kube_vip_address: \"${test_ip}\"/" /etc/kubez/globals.yml
#                    sed -i "s/^#kube_vip_port: .*/kube_vip_port: \"8443\"/" /etc/kubez/globals.yml
#                    vip_found=1
#                    break
#                fi
#            done
# 启用高可用配置
            sed -i "s/^#enable_kubernetes_ha: .*/enable_kubernetes_ha: \"yes\"/" /etc/kubez/globals.yml
            sed -i "s/^#kube_vip_port: .*/kube_vip_port: \"8443\"/" /etc/kubez/globals.yml
            cat /etc/kubez/globals.yml
#            if [ $vip_found -eq 0 ]; then
#                log error "无法找到可用的 VIP 地址"
#                exit 1
#            fi
        else
            log info "使用多节点非高可用配置"
        fi
    else
        log info "使用单节点配置"
    fi

    log info "globals.yml 配置完成"
}

# 修改 setup_kubernetes 函数，添加重置检查和更新 inventory
function setup_kubernetes() {
    # 首先检查并重置已有的 Kubernetes 配置
    check_and_reset_kubernetes
    
    # 更新 inventory 配置
    if [ ! -f "${NODE_CONFIG_FILE}" ]; then
        update_inventory || { log error "更新 inventory 配置失败"; exit 1; }
    fi
    
    # 创建必要目录
    mkdir -p /etc/kubez
    mkdir -p /data/prometheus /data/grafana

#    # 检查并备份 globals.yml
#    if [ -f "/etc/kubez/globals.yml" ]; then
#        local timestamp=$(date +%Y%m%d_%H%M%S)
#        cp -f /etc/kubez/globals.yml "/etc/kubez/globals.yml.bak.${timestamp}" || { log error "备份 globals.yml 失败"; exit 1; }
#    fi
#
#    # 使用新的配置文件
#    cp -f "${PKGPWD}/kubez-ansible-offline-master/etc/kubez/globals.yml" /etc/kubez/globals.yml || { log error "复制新的 globals.yml 失败"; exit 1; }
#
#    # 修改 globals.yml 配置
#    sed -i "s/kube_release: .*/kube_release: ${KUBE_VERSION}/g" /etc/kubez/globals.yml
#    sed -i "s/network_interface: .*/network_interface: \"${NETWORK_INTERFACE}\"/g" /etc/kubez/globals.yml
#    sed -i "s|yum_baseurl: .*|yum_baseurl: \"${YUM_REPO}\"|g" /etc/kubez/globals.yml
#    sed -i "s|image_repository: .*|image_repository: \"${LOCAL_REGISTRY}\"|g" /etc/kubez/globals.yml
#    sed -i "s|image_repository_container: .*|image_repository_container: \"${CONTAINER_REGISTRY}\"|g" /etc/kubez/globals.yml
#    sed -i "s/cluster_cidr: .*/cluster_cidr: \"172.30.0.0\/16\"/g" /etc/kubez/globals.yml
#    sed -i "s/service_cidr: .*/service_cidr: \"10.254.0.0\/16\"/g" /etc/kubez/globals.yml
    setup_globals_config || { log error "配置 globals.yml 失败"; exit 1; }
    # 执行Kubernetes安装
    ${KUBEZ_ANSIBLE_CMD} bootstrap-servers || { log error "bootstrap-servers 执行失败"; exit 1; }
    ${KUBEZ_ANSIBLE_CMD} deploy || { log error "deploy 执行失败"; exit 1; }
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
# 检查 Harbor 连接状态并尝试恢复
function check_harbor_connectivity_recover() {
    log info "检查 Harbor 连接状态..."

    # 尝试访问 Harbor API
    if ! curl -s -f "http://${IP_ADDRESS}:${HARBOR_PORT}/api/v2.0/health" &>/dev/null; then
        log warn "Harbor 服务不可访问，尝试重启服务..."

        # 检查 Harbor 服务状态
        if systemctl status harbor &>/dev/null; then
            # 服务存在，尝试重启
            log info "尝试重启 Harbor 服务..."
            if ! systemctl restart harbor; then
                log error "Harbor 服务重启失败，尝试重新安装"
                cleanup_harbor_data
                install_harbor
                return
            fi

            # 等待服务启动
            local max_retries=30
            local count=0
            while [ $count -lt $max_retries ]; do
                if curl -s -f "http://${IP_ADDRESS}:${HARBOR_PORT}/api/v2.0/health" &>/dev/null; then
                    log info "Harbor 服务已恢复"
                    return 0
                fi
                log info "等待 Harbor 服务就绪... (${count}/${max_retries})"
                sleep 5
                ((count++))
            done

            # 重启后仍无法访问，执行重装
            log error "Harbor 服务重启后仍无法访问，尝试重新安装"
            cleanup_harbor_data
            install_harbor
        else
            # 服务不存在，直接重装
            log error "Harbor 服务不存在，执行安装"
            cleanup_harbor_data
            install_harbor
        fi
    else
        log info "Harbor 服务运行正常"
        return 0
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
    if [ -n "$hostname" ] && \
       [ "$hostname" != "localhost" ] && \
       [ "$hostname" != "localhost.localdomain" ] && \
       [ "$hostname" != "127.0.0.1" ] && \
       [ "$hostname" != "::1" ]; then
        log info "使用有效的hostname: ${hostname}"
        echo "$hostname"
        return 0
    fi
    
    # 如果没有有效的 hostname，返回 IP 地址
    log info "未检测到有效的hostname，使用IP地址: ${ip}"
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
    
    # 使用节点配置生成 inventory 内容
    {
        # master 部分
        echo "[master] # 主节点组"
        echo "# 填节点hostname，即IP地址"
        if [ -f "${NODE_CONFIG_FILE}" ]; then
            # 多节点模式：从配置文件读取master节点
            grep -A10 "^\[docker-master\]" "${NODE_CONFIG_FILE}" | grep -v "^\[" | grep -v "^$" | awk '{print $1}'
        else
            # 单节点模式：使用当前节点
            get_node_hostname
        fi
        echo ""
        
        # worker 部分
        echo "[worker] # 计算节点组"
        echo "# 填节点hostname，即IP地址"
        if [ -f "${NODE_CONFIG_FILE}" ]; then
            # 多节点模式：从配置文件读取worker节点
            grep -A10 "^\[docker-node\]" "${NODE_CONFIG_FILE}" | grep -v "^\[" | grep -v "^$" | awk '{print $1}'
        else
            # 单节点模式：使用当前节点
            get_node_hostname
        fi
        echo ""
        
        # chrony 部分
        echo "[chrony] # 时间服务器，只设置1台"
        echo "# 填节点hostname，即IP地址"
        if [ -f "${NODE_CONFIG_FILE}" ]; then
            # 多节点模式：使用第一个master节点作为时间服务器
            grep -A10 "^\[docker-master\]" "${NODE_CONFIG_FILE}" | grep -v "^\[" | grep -v "^$" | head -n 1 | awk '{print $1}'
        else
            # 单节点模式：使用当前节点
            get_node_hostname
        fi
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

    # 获取节点信息
    if [ -f "${NODE_CONFIG_FILE}" ]; then
        # 多节点模式：从配置文件读取节点信息
        MASTER_NODE=$(grep -A10 "^\[docker-master\]" "${NODE_CONFIG_FILE}" | grep -v "^\[" | grep -v "^$" | head -n 1 | awk '{print $1}')
        WORKER_NODES=$(grep -A10 "^\[docker-node\]" "${NODE_CONFIG_FILE}" | grep -v "^\[" | grep -v "^$" | awk '{print $1}' | tr '\n' ',')
    else
        # 单节点模式：使用当前节点
        MASTER_NODE=$(get_node_hostname)
        WORKER_NODES="${MASTER_NODE}"
    fi

    # 安装步骤
    ansible-playbook -i inventory.ini -e "offline=1" scripts/ansible/playbooks/install_packages_and_dependencies.yml || { 
        log error "安装uni-virt依赖失败"; 
        exit 1; 
    }
    
    ansible-playbook -i inventory.ini scripts/ansible/playbooks/install_and_setup_chrony.yml || { 
        log error "设置集群时区失败"; 
        exit 1; 
    }
    
    # 检查并更新所有节点的标签
    log info "检查并更新节点标签..."
    local nodes=$(kubectl get nodes -o name)
    if [ -n "$nodes" ]; then
        for node in $nodes; do
            node_name=${node#node/}
        # 尝试删除已存在的标签
            kubectl label node ${node_name} doslab/virt.tool.centos- --overwrite=true || true
        # 重新添加标签
            kubectl label node ${node_name} doslab/virt.tool.centos="" --overwrite=true || {
                log error "更新节点 ${node_name} 标签失败"
            exit 1
        }
        done
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
    log info "开始卸载 Kubernetes 集群，inventory: $INVENTORY"
    
    # 先卸载 Kube-OVN
    uninstall_kube_ovn
    
    # 然后卸载 Kubernetes 集群
    ${KUBEZ_ANSIBLE_CMD} destroy --yes-i-really-really-mean-it || { 
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
    echo "  crossplane   仅安装 Crossplane"
    echo "  check_and_upload  仅检查文件并上传镜像和RPM包"
    echo "  volcano      仅安装 Volcano"
    echo ""
    echo "其他命令:"
    echo "  destroy      卸载系统"
    echo "  help        显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  HARBOR_PORT      设置Harbor端口 (默认: 8080)"
    echo "  UNIVIRT_VERSION  设置UniVirt版本 (默认: v1.0.0.lab)"
    echo ""
    echo "多节点部署说明:"
    echo "  1. 确保已创建 multinode 配置文件，包含必要的节点组"
    echo "  2. 确保所有节点之间可以通过主机名互相访问"
    echo "  3. 确保部署节点可以SSH免密登录到所有其他节点"
    echo "  4. 节点配置文件将直接用作 inventory 文件"
    echo ""
    echo "示例:"
    echo "  $0 install all                                  # 完整安装所有组件"
    echo "  $0 install harbor                              # 仅安装 Harbor"
    echo "  HARBOR_PORT=9090 $0 install harbor            # 使用自定义端口安装 Harbor"
    echo "  UNIVIRT_VERSION=v2.0.0 $0 install univirt    # 安装指定版本的 UniVirt"
    echo "  $0 install check_and_upload                   # 仅检查文件并上传镜像和RPM包"
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
            rm -rf "$dir"/* 2>/dev/null || log error "清理 $dir 内容失败，但将继续执行"
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

# --- 查找可用的镜像 ---
#function find_available_image() {
#    local image_pattern="$1"
#    local image_name="$2"
#
#    log info "正在查找 $image_name 镜像..."
#
#    # 使用docker images查找匹配的镜像
#    local found_image=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "^${image_pattern}" | head -1)
#
#    if [[ -n "$found_image" ]]; then
#        log info "找到 $image_name 镜像: $found_image"
#        echo "$found_image"
#        return 0
#    else
#        log error "未找到 $image_name 镜像，请确保已拉取相关镜像"
#        log error "可以使用以下命令拉取镜像:"
#        case "$image_name" in
#            "Prometheus")
#                log error "  docker pull prom/prometheus:latest"
#                ;;
#            "Grafana")
#                log error "  docker pull grafana/grafana:latest"
#                ;;
#            "KSM")
#                log error "  docker pull registry.k8s.io/kube-state-metrics/kube-state-metrics:latest"
#                ;;
#        esac
#        return 1
#    fi
#}
# 查找可用镜像的辅助函数 - 修复版本
function find_available_image() {
    local pattern="$1"
    local component_name="$2"

    # 使用 docker images 查找匹配的镜像，只输出镜像名称，不输出日志到 stdout
    local available_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^${pattern}" | head -n 1)

    if [[ -n "$available_images" ]]; then
        log info "找到 ${component_name} 镜像: $available_images" >&2  # 日志输出到 stderr
        echo "$available_images"  # 只有镜像名称输出到 stdout
        return 0
    else
        log warn "未找到 ${component_name} 镜像 (模式: ${pattern})" >&2  # 日志输出到 stderr
        return 1
    fi
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
        # 在 check_prerequisites 函数中添加 Volcano 检查分支
        "volcano")
            log info "执行 Volcano 安装前检查..."
            # 检查 kubectl 和集群状态
            if ! check_cluster_communication; then
                check_failed=1
            fi

            # 检查 helm 是否安装
            if ! command -v helm &>/dev/null; then
                log error "Helm 未安装"
                check_failed=1
            fi

            # 检查 Volcano helm chart
            if ! find "${OTHERS_DIR}" -name "volcano-*.tgz" -type f &>/dev/null; then
                log error "未找到 Volcano helm chart 文件"
                check_failed=1
            fi
            ;;
         "volcano-monitoring")
            log info "检查 Volcano 监控组件安装前提条件..."

            # 检查kubectl是否可用
            if ! command -v kubectl &> /dev/null; then
                log error "kubectl 未安装或不可用"
                return 1
            fi

            # 检查Docker是否可用
            if ! command -v docker &> /dev/null; then
                log error "Docker 命令不可用，请确保 Docker 已安装并正在运行"
                return 1
            fi

            # 检查YAML文件是否存在
#            local yaml_file="${OTHERS_DIR}/volcano-monitoring-latest.yaml"
#            if [[ ! -f "$yaml_file" ]]; then
#                log error "YAML文件不存在: $yaml_file"
#                log error "请确保 others 目录下存在 volcano-monitoring-latest.yaml 文件"
#                return 1
#            fi
    # 检查YAML文件是否存在
            local yaml_file="${OTHERS_DIR}/${VOLCANO_MONITORING_YAML_FILE}"  # 修改：使用变量
            if [[ ! -f "$yaml_file" ]]; then
                log error "YAML文件不存在: $yaml_file"
                log error "请确保 others 目录下存在 ${VOLCANO_MONITORING_YAML_FILE} 文件"  # 修改：使用变量
                return 1
            fi

            # 检查并查找可用镜像
            log info "开始检查可用镜像..."

            # 查找Prometheus镜像
            local prometheus_image=$(find_available_image "prom/prometheus" "Prometheus")
            if [[ -z "$prometheus_image" ]]; then
                log error "请先拉取 Prometheus 镜像: docker pull prom/prometheus:latest"
                return 1
            fi
            export VOLCANO_PROMETHEUS_IMAGE="$prometheus_image"

            # 查找Grafana镜像
            local grafana_image=$(find_available_image "grafana/grafana" "Grafana")
            if [[ -z "$grafana_image" ]]; then
                log error "请先拉取 Grafana 镜像: docker pull grafana/grafana:latest"
                return 1
            fi
            export VOLCANO_GRAFANA_IMAGE="$grafana_image"

            # 查找KSM镜像（可选）
            local ksm_image=""
            local ksm_candidates=(
                "docker.io/volcanosh/kube-state-metrics"
                "registry.k8s.io/kube-state-metrics/kube-state-metrics"
                "k8s.gcr.io/kube-state-metrics/kube-state-metrics"
                "quay.io/coreos/kube-state-metrics"
            )

            for pattern in "${ksm_candidates[@]}"; do
                ksm_image=$(find_available_image "$pattern" "KSM")
                if [[ -n "$ksm_image" ]]; then
                    break
                fi
            done

            if [[ -z "$ksm_image" ]]; then
                log info "未找到KSM镜像，将跳过KSM镜像替换"
                log info "建议拉取KSM镜像: docker pull registry.k8s.io/kube-state-metrics/kube-state-metrics:latest"
                export VOLCANO_KSM_IMAGE=""
            else
                export VOLCANO_KSM_IMAGE="$ksm_image"
            fi

            log info "Volcano 监控组件前提条件检查完成"
            log info "  YAML文件: ${VOLCANO_MONITORING_YAML_FILE}"  # 新增：显示使用的YAML文件名
            log info "  命名空间: $VOLCANO_MONITORING_NAMESPACE"
            log info "  Prometheus 镜像: $VOLCANO_PROMETHEUS_IMAGE"
            log info "  Grafana 镜像: $VOLCANO_GRAFANA_IMAGE"
            if [[ -n "$VOLCANO_KSM_IMAGE" ]]; then
                log info "  KSM 镜像: $VOLCANO_KSM_IMAGE"
            fi
            log info "  镜像拉取策略: $VOLCANO_MONITORING_IMAGE_PULL_POLICY"
            ;;
        "crossplane")
            log info "执行 Crossplane 安装前检查..."
            # 检查 kubectl 和集群状态
            if ! check_cluster_communication; then
                check_failed=1
            fi

            # 检查 helm 是否安装
            if ! command -v helm &>/dev/null; then
                log error "Helm 未安装"
                check_failed=1
            fi

            # 检查必要的文件
            if [ ! -d "${IMAGE_DIR}/crossplane" ]; then
                log error "Crossplane 镜像目录不存在: ${IMAGE_DIR}/crossplane"
                check_failed=1
            fi

            # 检查 provider-kubernetes 镜像文件
            if ! find "${IMAGE_DIR}/crossplane" -name "provider-kubernetes*.tar" -type f &>/dev/null; then
                log error "未找到 provider-kubernetes 镜像文件"
                check_failed=1
            fi

            # 检查 Crossplane helm chart
            if ! find "${OTHERS_DIR}" -name "crossplane-*.tgz" -type f &>/dev/null; then
                log error "未找到 Crossplane helm chart 文件"
                check_failed=1
            fi

            # 检查 Harbor 是否可用
            if ! check_harbor_connectivity_recover; then
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
function test_function() {
    local function_name=$1
    shift
    
    # 解析参数为键值对
    declare -A params
    for arg in "$@"; do
        IFS='=' read -r key value <<< "$arg"
        params["$key"]="$value"
    done

    # 动态调用函数并传递参数
    if declare -f "$function_name" > /dev/null; then
        # 将参数转换为环境变量
        for key in "${!params[@]}"; do
            export "$key"="${params[$key]}"
        done
        
        log info "开始测试函数：$function_name"
        "$function_name"
        local ret=$?
        log info "函数测试完成，返回值：$ret"
        return $ret
    else
        log error "函数不存在：$function_name"
        return 1
    fi
}

#function install_volcano_monitoring() {
#    log info "开始安装 Volcano 监控组件..."
#
#    # 使用预设的变量
#    local namespace="$VOLCANO_MONITORING_NAMESPACE"
#    local prometheus_image="$VOLCANO_PROMETHEUS_IMAGE"
#    local grafana_image="$VOLCANO_GRAFANA_IMAGE"
#    local ksm_image="$VOLCANO_KSM_IMAGE"
#    local image_pull_policy="$VOLCANO_MONITORING_IMAGE_PULL_POLICY"
#
#    # 检查YAML文件
#    local original_yaml_file="${OTHERS_DIR}/${VOLCANO_MONITORING_YAML_FILE}"
#    local modified_yaml_file="${OTHERS_DIR}/volcano-monitoring-modified-$(date +%Y%m%d%H%M%S).yaml"
#
#    # 提取旧namespace
#    local old_namespace=$(awk '/namespace:/ {print $2; exit}' "$yaml_file")
#    if [[ -z "$old_namespace" ]]; then
#        log error "无法从 YAML 中检测 namespace"
#        return 1
#    fi
#    log info "检测到旧 namespace: $old_namespace"
#
#    # 镜像替换关键词
#    local old_prometheus_image="prom/prometheus"
#    local old_ksm_pattern="docker\.io/volcanosh/kube-state-metrics"
#    local old_grafana_image="grafana/grafana"
#
#    # 备份原文件
#    local backup_file="${yaml_file}.bak.$(date +%Y%m%d%H%M%S)"
#    cp "$yaml_file" "$backup_file"
#    log info "已备份原文件至: $backup_file"
#
#    # sed 第一阶段替换
#    local temp_sed="${yaml_file}.tmp.sed"
##    local sed_cmds=(
##        -e "s|\([[:space:]]*namespace: \)${old_namespace}\b|\1${namespace}|g"
##        -e "s|image: ${old_prometheus_image}[^[:space:]]*|image: ${prometheus_image}|g"
##        -e "s|image: ${old_grafana_image}[^[:space:]]*|image: ${grafana_image}|g"
##        -e "s|^\([[:space:]]*imagePullPolicy:\s*\).*|\1${image_pull_policy}|g"
##        -e "s|\(alertmanager\.\)${old_namespace}\(\.svc\)|\1${namespace}\2|g"
##        -e "s|\(kube-state-metrics\.\)${old_namespace}\(\.svc\.cluster\.local\)|\1${namespace}\2|g"
##        -e "s|\(prometheus-service\.\)${old_namespace}\(\.svc\)|\1${namespace}\2|g"
##    )
#    local sed_cmds=(
#        -e "s|\\([[:space:]]*namespace:[[:space:]]*\\)${old_namespace}\\b|\\1${namespace}|g"
#        -e "s|image:[[:space:]]*${old_prometheus_pattern}[^[:space:]]*|image: ${prometheus_image}|g"
#        -e "s|image:[[:space:]]*${old_grafana_pattern}[^[:space:]]*|image: ${grafana_image}|g"
#        -e "s|^\\([[:space:]]*imagePullPolicy:[[:space:]]*\\).*|\\1${image_pull_policy}|g"
#        -e "s|\\(alertmanager\\.\\)${old_namespace}\\(\\.svc\\)|\\1${namespace}\\2|g"
#        -e "s|\\(kube-state-metrics\\.\\)${old_namespace}\\(\\.svc\\.cluster\\.local\\)|\\1${namespace}\\2|g"
#        -e "s|\\(prometheus-service\\.\\)${old_namespace}\\(\\.svc\\)|\\1${namespace}\\2|g"
#    )
#
#    # KSM 替换是可选的
#    if [[ -n "$ksm_image" ]]; then
#        sed_cmds+=("-e" "s|image: ${old_ksm_image}[^[:space:]]*|image: ${ksm_image}|g")
#    fi
#
#    sed "${sed_cmds[@]}" "$yaml_file" > "$temp_sed"
#
#    # 第二阶段：确保所有容器都有 imagePullPolicy
#    local temp_final="${yaml_file}.tmp"
#    awk -v policy="$image_pull_policy" '
#      BEGIN { in_container = 0; image_line = ""; inserted = 0 }
#      {
#        if ($0 ~ /^[[:space:]]*-[[:space:]]*name:/ || $0 ~ /^[[:space:]]*containers:/) {
#          in_container = 1
#          inserted = 0
#        }
#
#        if (in_container && $0 ~ /^[[:space:]]*image:[[:space:]]*/) {
#          image_line = $0
#          indent = match($0, /[^ ]/) - 1
#          image_indent = substr($0, 1, indent)
#        }
#
#        if (in_container && $0 ~ /^[[:space:]]*imagePullPolicy:/) {
#          inserted = 1
#        }
#
#        print $0
#
#        if (in_container && $0 == image_line && inserted == 0) {
#          print image_indent "imagePullPolicy: " policy
#          inserted = 1
#        }
#      }
#    ' "$temp_sed" > "$temp_final"
#
#    # 应用最终修改
#    if [[ $? -eq 0 ]]; then
#        mv "$temp_final" "$yaml_file"
#        rm -f "$temp_sed"
#        log info "YAML 文件修改完成: $yaml_file"
#
#        # 应用 Kubernetes 配置
#        log info "开始部署 Volcano 监控组件..."
#        if kubectl apply -f "$yaml_file"; then
#            log info "Volcano 监控组件部署成功"
#            log info ""
#            log info "部署信息:"
#            log info "   命名空间: $namespace"
#            log info "   Prometheus 镜像: $prometheus_image"
#            log info "   Grafana 镜像: $grafana_image"
#            if [[ -n "$ksm_image" ]]; then
#                log info "   KSM 镜像: $ksm_image"
#            fi
#            log info "   镜像拉取策略: $image_pull_policy"
#            log info ""
#            log info "检查部署状态:"
#            kubectl get pods -n "$namespace"
#            return 0
#        else
#            log error "Volcano 监控组件部署失败"
#            return 1
#        fi
#    else
#        log error "YAML 文件处理失败"
#        rm -f "$temp_sed" "$temp_final"
#        return 1
#    fi
#}


function install_volcano_monitoring() {
    log info "开始安装 Volcano 监控组件..."

    # 使用预设的变量
    local namespace="$VOLCANO_MONITORING_NAMESPACE"
    local prometheus_image="$VOLCANO_PROMETHEUS_IMAGE"
    local grafana_image="$VOLCANO_GRAFANA_IMAGE"
    local ksm_image="$VOLCANO_KSM_IMAGE"
    local image_pull_policy="$VOLCANO_MONITORING_IMAGE_PULL_POLICY"

    # 调试信息 - 检查镜像变量内容
    log info "调试信息 - 镜像变量内容:"
    log info "  Prometheus: '$prometheus_image'"
    log info "  Grafana: '$grafana_image'"
    log info "  KSM: '$ksm_image'"

    # 清理镜像变量中可能包含的日志信息
    prometheus_image=$(echo "$prometheus_image" | tail -1 | grep -E '^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$' || echo "$prometheus_image")
    grafana_image=$(echo "$grafana_image" | tail -1 | grep -E '^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$' || echo "$grafana_image")
    if [[ -n "$ksm_image" ]]; then
        ksm_image=$(echo "$ksm_image" | tail -1 | grep -E '^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$' || echo "$ksm_image")
    fi

    log info "清理后的镜像变量:"
    log info "  Prometheus: '$prometheus_image'"
    log info "  Grafana: '$grafana_image'"
    log info "  KSM: '$ksm_image'"

    # 原始YAML文件和修改后的文件
    local original_yaml_file="${OTHERS_DIR}/${VOLCANO_MONITORING_YAML_FILE}"
    local modified_yaml_file="${OTHERS_DIR}/volcano-monitoring-modified-$(date +%Y%m%d%H%M%S).yaml"

    # 检查原始YAML文件是否存在
    if [[ ! -f "$original_yaml_file" ]]; then
        log error "原始YAML文件不存在: $original_yaml_file"
        return 1
    fi

    log info "使用原始文件: $original_yaml_file"
    log info "生成修改后文件: $modified_yaml_file"

    # 提取旧namespace - 改进检测方法
    local old_namespace=$(grep -E "^\s*namespace:\s*" "$original_yaml_file" | head -1 | awk '{print $2}')
    if [[ -z "$old_namespace" ]]; then
        log error "无法从 YAML 中检测 namespace"
        return 1
    fi
    log info "检测到旧 namespace: $old_namespace"

    # 检查目标命名空间是否存在，如果不存在则创建
    log info "检查命名空间: $namespace"
    if kubectl get namespace "$namespace" &>/dev/null; then
        log info "命名空间 '$namespace' 已存在"
    else
        log info "命名空间 '$namespace' 不存在，正在创建..."
        if kubectl create namespace "$namespace"; then
            log info "命名空间 '$namespace' 创建成功"
        else
            log error "创建命名空间 '$namespace' 失败"
            return 1
        fi
    fi

    # 为命名空间添加标签（可选，便于管理）
    log info "为命名空间添加标签..."
    kubectl label namespace "$namespace" app=volcano-monitoring --overwrite &>/dev/null || {
        log warn "添加命名空间标签失败，但不影响部署"
    }

    # 使用 awk 进行安全的字符串替换
    log info "开始处理 YAML 文件内容..."

    # 创建临时文件
    local temp_file="${modified_yaml_file}.tmp"

    # 使用 awk 进行所有替换操作 - 修复镜像替换问题
    if ! awk -v old_ns="$old_namespace" \
             -v new_ns="$namespace" \
             -v prom_img="$prometheus_image" \
             -v grafana_img="$grafana_image" \
             -v ksm_img="$ksm_image" \
             -v pull_policy="$image_pull_policy" '
    {
        line = $0

        # 替换命名空间 - 使用字符串匹配
        if (match(line, /^[[:space:]]*namespace:[[:space:]]*/) && index(line, old_ns)) {
            sub(/namespace:[[:space:]]*[^[:space:]]*/, "namespace: " new_ns, line)
        }

        # 替换 Prometheus 镜像 - 更精确的匹配
        if (match(line, /^[[:space:]]*image:[[:space:]]*prom\/prometheus/)) {
            sub(/image:[[:space:]]*prom\/prometheus[^[:space:]]*/, "image: " prom_img, line)
        }

        # 替换 Grafana 镜像 - 更精确的匹配
        if (match(line, /^[[:space:]]*image:[[:space:]]*grafana\/grafana/)) {
            sub(/image:[[:space:]]*grafana\/grafana[^[:space:]]*/, "image: " grafana_img, line)
        }

        # 替换 KSM 镜像（如果提供）
        if (ksm_img != "" && match(line, /^[[:space:]]*image:[[:space:]]*docker\.io\/volcanosh\/kube-state-metrics/)) {
            sub(/image:[[:space:]]*docker\.io\/volcanosh\/kube-state-metrics[^[:space:]]*/, "image: " ksm_img, line)
        }

        # 替换 imagePullPolicy
        if (match(line, /^[[:space:]]*imagePullPolicy:[[:space:]]*/)) {
            sub(/imagePullPolicy:[[:space:]]*[^[:space:]]*/, "imagePullPolicy: " pull_policy, line)
        }

        # 替换服务引用中的命名空间 - 使用字符串替换
        if (index(line, "alertmanager." old_ns ".svc")) {
            gsub("alertmanager\\." old_ns "\\.svc", "alertmanager." new_ns ".svc", line)
        }
        if (index(line, "kube-state-metrics." old_ns ".svc.cluster.local")) {
            gsub("kube-state-metrics\\." old_ns "\\.svc\\.cluster\\.local", "kube-state-metrics." new_ns ".svc.cluster.local", line)
        }
        if (index(line, "prometheus-service." old_ns ".svc")) {
            gsub("prometheus-service\\." old_ns "\\.svc", "prometheus-service." new_ns ".svc", line)
        }

        print line
    }' "$original_yaml_file" > "$temp_file"; then
        log error "awk 处理失败"
        rm -f "$temp_file"
        return 1
    fi

    # 第二阶段：确保所有容器都有 imagePullPolicy
    log info "确保所有容器都有 imagePullPolicy 配置..."
    if ! awk -v policy="$image_pull_policy" '
      BEGIN {
        in_container = 0
        image_line = ""
        inserted = 0
        image_indent = ""
      }
      {
        # 检测容器开始
        if ($0 ~ /^[[:space:]]*-[[:space:]]*name:/ || $0 ~ /^[[:space:]]*containers:/) {
          in_container = 1
          inserted = 0
        }

        # 检测到新的顶级段落，重置状态
        if ($0 ~ /^[^[:space:]]/ && $0 !~ /^[[:space:]]*-/) {
          in_container = 0
        }

        # 记录镜像行
        if (in_container && $0 ~ /^[[:space:]]*image:[[:space:]]*/) {
          image_line = $0
          # 计算缩进
          indent_match = match($0, /[^ ]/)
          if (indent_match > 0) {
            image_indent = substr($0, 1, indent_match - 1)
          }
        }

        # 检查是否已有 imagePullPolicy
        if (in_container && $0 ~ /^[[:space:]]*imagePullPolicy:/) {
          inserted = 1
        }

        # 输出当前行
        print $0

        # 在镜像行后插入 imagePullPolicy（如果还没有）
        if (in_container && $0 == image_line && inserted == 0 && image_indent != "") {
          print image_indent "imagePullPolicy: " policy
          inserted = 1
        }
      }
    ' "$temp_file" > "$modified_yaml_file"; then
        log error "imagePullPolicy 处理失败"
        rm -f "$temp_file"
        return 1
    fi

    # 清理临时文件
    rm -f "$temp_file"

    # 验证生成的文件
    if [[ ! -f "$modified_yaml_file" ]]; then
        log error "修改后的 YAML 文件生成失败"
        return 1
    fi

    # 检查文件是否为空
    if [[ ! -s "$modified_yaml_file" ]]; then
        log error "修改后的 YAML 文件为空"
        rm -f "$modified_yaml_file"
        return 1
    fi

    # 验证生成的 YAML 文件中的镜像字段
    log info "验证生成的 YAML 文件中的镜像..."
    local prom_check=$(grep -E "^\s*image:\s*.*prom.*" "$modified_yaml_file" | head -1)
    local grafana_check=$(grep -E "^\s*image:\s*.*grafana.*" "$modified_yaml_file" | head -1)

    if [[ -n "$prom_check" ]]; then
        log info "Prometheus 镜像行: $prom_check"
    fi
    if [[ -n "$grafana_check" ]]; then
        log info "Grafana 镜像行: $grafana_check"
    fi

    log info "YAML 文件修改完成: $modified_yaml_file"

    # 显示修改摘要
    log info "修改摘要:"
    log info "  原始文件: $(basename $original_yaml_file)"
    log info "  修改后文件: $(basename $modified_yaml_file)"
    log info "  命名空间: $old_namespace -> $namespace"
    log info "  Prometheus 镜像: $prometheus_image"
    log info "  Grafana 镜像: $grafana_image"
    if [[ -n "$ksm_image" ]]; then
        log info "  KSM 镜像: $ksm_image"
    fi
    log info "  镜像拉取策略: $image_pull_policy"

    # 验证命名空间再次确认存在
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log error "命名空间 '$namespace' 不存在，无法继续部署"
        return 1
    fi

    # 应用 Kubernetes 配置
    log info "开始部署 Volcano 监控组件到命名空间: $namespace"
    if kubectl apply -f "$modified_yaml_file"; then
        log info "Volcano 监控组件部署成功"

        # 等待 Pod 启动
        log info "等待 Pod 启动..."
        local max_wait=60
        local wait_count=0
        while [ $wait_count -lt $max_wait ]; do
            local pod_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
            if [ "$pod_count" -gt 0 ]; then
                log info "检测到 Pod 已开始创建"
                break
            fi
            sleep 2
            ((wait_count++))
        done

        log info ""
        log info "部署信息:"
        log info "   原始YAML文件: ${VOLCANO_MONITORING_YAML_FILE}"
        log info "   使用的配置文件: $(basename $modified_yaml_file)"
        log info "   命名空间: $namespace"
        log info "   Prometheus 镜像: $prometheus_image"
        log info "   Grafana 镜像: $grafana_image"
        if [[ -n "$ksm_image" ]]; then
            log info "   KSM 镜像: $ksm_image"
        fi
        log info "   镜像拉取策略: $image_pull_policy"
        log info ""
        log info "检查部署状态:"
        kubectl get pods -n "$namespace"
        log info ""
        log info "检查服务状态:"
        kubectl get svc -n "$namespace"

        # 可选：保留修改后的文件供后续使用
        log info "修改后的配置文件已保存: $modified_yaml_file"
        return 0
    else
        log error "Volcano 监控组件部署失败"
        log error "修改后的配置文件位置: $modified_yaml_file"
        log error "请检查命名空间 '$namespace' 中的资源状态:"
        kubectl get all -n "$namespace" 2>/dev/null || log error "无法获取命名空间资源信息"
        return 1
    fi
}




# 设置 Crossplane 相关环境变量
function set_crossplane_env() {
    # 从镜像文件名提取版本号
    local crossplane_dir="${IMAGE_DIR}/crossplane"
    local provider_tar=$(find "${crossplane_dir}" -name "provider-kubernetes*.tar" | head -n 1)

    if [ -z "${provider_tar}" ]; then
        log error "未找到 provider-kubernetes 镜像文件"
        return 1
    fi

    # 提取版本号
    CROSSPLANE_VERSION=$(basename "${provider_tar}" | grep -oP 'v\d+\.\d+\.\d+' || echo "")
    if [ -z "${CROSSPLANE_VERSION}" ]; then
        log error "未指定 provider-kubernetes 版本"
        provider_version=latest
    fi

    # 设置镜像相关变量
    export CROSSPLANE_SOURCE_IMAGE="xpkg.upbound.io/upbound/provider-kubernetes:${CROSSPLANE_VERSION}"
    export CROSSPLANE_TARGET_IMAGE="${CONTAINER_REGISTRY}/library/provider-kubernetes:${CROSSPLANE_VERSION}"

    log info "Crossplane 环境变量设置完成:
    版本: ${CROSSPLANE_VERSION}
    源镜像: ${CROSSPLANE_SOURCE_IMAGE}
    目标镜像: ${CROSSPLANE_TARGET_IMAGE}"

    return 0
}

# 修改后的推送镜像函数
function push_crossplane_images() {
    log info "开始推送 Crossplane 镜像..."

    # 设置环境变量
    if ! set_crossplane_env; then
        return 1
    fi

    # 加载镜像
    local provider_tar=$(find "${IMAGE_DIR}/crossplane" -name "provider-kubernetes*.tar" | head -n 1)
    log info "加载 provider-kubernetes 镜像: ${provider_tar}"
    if ! docker load -i "${provider_tar}"; then
        log error "加载镜像失败"
        return 1
    fi

    # 标记并推送镜像
    log info "标记镜像: ${CROSSPLANE_SOURCE_IMAGE} -> ${CROSSPLANE_TARGET_IMAGE}"
    if ! docker tag "${CROSSPLANE_SOURCE_IMAGE}" "${CROSSPLANE_TARGET_IMAGE}"; then
        log error "标记镜像失败"
        return 1
    fi

    log info "推送镜像到 Harbor: ${CROSSPLANE_TARGET_IMAGE}"
    if ! docker push "${CROSSPLANE_TARGET_IMAGE}"; then
        log error "推送镜像失败"
        return 1
    fi

    log info "Crossplane 镜像推送完成"
    return 0
}
## 推送 Crossplane 镜像到 Harbor
#function push_crossplane_images() {
#    log info "开始推送 Crossplane 镜像..."
#
#    local crossplane_dir="${IMAGE_DIR}/crossplane"
#    if [ ! -d "${crossplane_dir}" ]; then
#        log error "Crossplane 镜像目录不存在: ${crossplane_dir}"
#        return 1
#    fi
#
#    # 查找 provider-kubernetes 镜像文件
#    local provider_tar=$(find "${crossplane_dir}" -name "provider-kubernetes*.tar" | head -n 1)
#    if [ -z "${provider_tar}" ]; then
#        log error "未找到 provider-kubernetes 镜像文件"
#        return 1
#    fi
#
#    # 提取版本号
#    local version=$(basename "${provider_tar}" | grep -oP 'v\d+\.\d+\.\d+' || echo "")
#    if [ -z "${version}" ]; then
#        log error "无法从文件名提取版本号: ${provider_tar}"
#        return 1
#    fi
#
#    # 加载镜像
#    log info "加载 provider-kubernetes 镜像: ${provider_tar}"
#    if ! docker load -i "${provider_tar}"; then
#        log error "加载镜像失败"
#        return 1
#    fi
#
#    # 标记并推送镜像
#    local source_image="xpkg.upbound.io/upbound/provider-kubernetes:${version}"
#    local target_image="${CONTAINER_REGISTRY}/library/provider-kubernetes:${version}"
#
#    log info "标记镜像: ${source_image} -> ${target_image}"
#    if ! docker tag "${source_image}" "${target_image}"; then
#        log error "标记镜像失败"
#        return 1
#    fi
#
#    log info "推送镜像到 Harbor: ${target_image}"
#    if ! docker push "${target_image}"; then
#        log error "推送镜像失败"
#        return 1
#    fi
#
#    log info "Crossplane 镜像推送完成"
#    return 0
#}
# 安装 Volcano
function install_volcano() {
    log info "开始安装 Volcano..."

    # 检查 helm 命令
    if ! command -v helm &>/dev/null; then
        log error "未找到 helm 命令"
        return 1
    fi

    # 查找 Volcano helm chart
    local chart_file=$(find "${OTHERS_DIR}" -name "volcano-*.tgz" | head -n 1)
    if [ -z "${chart_file}" ]; then
        log error "未找到 Volcano helm chart 文件"
        return 1
    fi

    # 提取版本号
    local version=$(basename "${chart_file}" | grep -oP '\d+\.\d+\.\d+(?=\.tgz)' || echo "")
    if [ -z "${version}" ]; then
        log error "无法从文件名提取版本号: ${chart_file}"
        return 1
    fi

    log info "使用 Helm 安装 Volcano 版本 ${version}..."

    # 尝试安装
    if helm install volcano "${chart_file}" \
        --set basic.image_pull_policy=IfNotPresent \
        --set basic.image_tag_version=v${version} \
        --namespace volcano-ljx \
        --create-namespace; then
        log info "Volcano 安装成功"
        return 0
    fi

    # 如果安装失败,检查是否是因为名称已存在
    if [[ $(helm list -n volcano-ljx | grep volcano) ]]; then
        log info "检测到已存在的 Volcano 安装,尝试升级..."

        # 尝试升级
        if helm upgrade volcano "${chart_file}" \
            --set basic.image_pull_policy=IfNotPresent \
            --set basic.image_tag_version=v${version} \
            --namespace volcano-ljx \
            --create-namespace; then
            log info "Volcano 升级成功"
            return 0
        else
            log error "Volcano 升级失败"
            return 1
        fi
    fi

    log error "Volcano 安装失败"
    return 1
}

# 安装 Crossplane
function install_crossplane() {
    log info "开始安装 Crossplane..."

    # 使用 kubez-ansible 安装 Crossplane
    log info "通过 kubez-ansible 安装 Crossplane..."
    if ! ${KUBEZ_ANSIBLE_CMD} apply --tag crossplane; then
        log error "通过 kubez-ansible 安装 Crossplane 失败"
#        return 1
    fi
    log info "通过 kubez-ansible 安装 Crossplane 完成"

    # 检查 helm 命令是否可用
    if ! command -v helm &>/dev/null; then
        log error "未找到 helm 命令"
        return 1
    fi

    # 查找 Crossplane helm chart
    local chart_file=$(find "${OTHERS_DIR}" -name "crossplane-*.tgz" | head -n 1)
    if [ -z "${chart_file}" ]; then
        log error "未找到 Crossplane helm chart 文件"
        return 1
    fi

    # 提取版本号
    local version=$(basename "${chart_file}" | grep -oP '\d+\.\d+\.\d+(?=\.tgz)' || echo "")
    if [ -z "${version}" ]; then
        log error "无法从文件名提取版本号: ${chart_file}"
        return 1
    fi

    # 创建命名空间
    if ! kubectl get namespace crossplane-system &>/dev/null; then
        log info "创建 crossplane-system 命名空间"
        if ! kubectl create namespace crossplane-system; then
            log error "创建命名空间失败"
            return 1
        fi
    fi

    # 查找 provider-kubernetes 版本
    if ! set_crossplane_env; then
        return 1
    fi

    # 安装 Crossplane
    log info "使用 Helm 安装 Crossplane ${version}"
    if ! helm install crossplane "${chart_file}" \
        --namespace crossplane-system \
        --set args='{--enable-external-secret-stores}' \
        --set image.tag="v${version}" \
        --set "provider.packages={${CROSSPLANE_TARGET_IMAGE}}"; then
        if [[ $(helm list -n crossplane-system | grep crossplane) ]]; then
            log info "检测到已存在的 Crossplane 安装,尝试升级..."

            # 尝试升级
            if ! helm upgrade crossplane "${chart_file}" \
                --namespace crossplane-system \
                --set "provider.packages={${CROSSPLANE_TARGET_IMAGE}}"; then
                log error "Crossplane 升级失败"
                return 1
            fi
        else
            log error "Crossplane 安装失败"
            return 1
        fi
    fi

    # 等待 Crossplane 就绪
    log info "等待 Crossplane 就绪..."
    local max_retries=30
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if kubectl -n crossplane-system get pods | grep -q "crossplane.*Running"; then
            log info "Crossplane 已就绪"
            return 0
        fi
        retry_count=$((retry_count + 1))
        sleep 10
    done

    log error "等待 Crossplane 就绪超时"
    return 1
}

# 修改 main 函数中的安装分支
function main() {
    case "$1" in
        "test")  
            if [ -z "$2" ]; then
                log error "请指定要测试的函数名"
                show_help
                exit 1
            fi
            init_env
            shift
            test_function "$@"
            ;;
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
#                    check_files true     # 检查所有文件
                    cleanup_old_data
                    install_nexus
                    process_materials
                    install_kubez_ansible
                    setup_kubernetes
                    install_kube_ovn
                    wait_kubernetes_ready
                    install_monitoring
                    install_harbor
                    push_crossplane_images
                    install_crossplane
                    install_volcano
                    install_volcano_monitoring
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

                "crossplane")
                    log info "开始安装 Crossplane..."
                    init_env
                    check_prerequisites "crossplane" || { log error "Crossplane 安装前检查失败"; exit 1; }
                    push_crossplane_images
                    install_crossplane
                    log info "Crossplane 安装完成"
                    ;;
                "volcano")
                    log info "开始安装 Volcano..."
                    init_env
                    check_prerequisites "volcano" || { log error "Volcano 安装前检查失败"; exit 1; }
                    install_volcano
                    log info "Volcano 安装完成"
                    ;;
                "volcano-monitoring")
                    log info "开始安装 Volcano 监控组件..."
                    init_env
                    check_prerequisites "volcano-monitoring" || { log error "Volcano 监控组件安装前检查失败"; exit 1; }
                    install_volcano_monitoring
                    log info "Volcano 监控组件安装完成"
                    ;;
                "check_and_upload")
                    log info "开始检查文件并上传镜像和RPM包..."
                    init_env
                    check_files true     # 检查所有文件
                    install_nexus        # 安装并启动Nexus
                    process_materials    # 处理材料（解压并上传镜像和RPM包）
                    log info "文件检查和上传完成"
                    ;;
                    
                *)
                    log error "未知的安装选项: $2"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
            
        "destroy")
            destroy_kubernetes
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

# 添加 Kube-OVN 卸载函数
function uninstall_kube_ovn() {
    log info "开始卸载 Kube-OVN..."
    
    # 检查 kubectl 命令是否可用
    if ! command -v kubectl &>/dev/null; then
        log warning "kubectl 命令不可用，跳过 Kube-OVN 资源清理"
        return 0
    fi
    
    # 检查 Kubernetes 集群是否可访问
    if ! kubectl get nodes &>/dev/null; then
        log warning "无法访问 Kubernetes 集群，跳过 Kube-OVN 资源清理"
        return 0
    fi
    
    # 检查清理脚本是否存在
    if [ -f "${OTHERS_DIR}/cleanup.sh" ]; then
        log info "执行 Kube-OVN 清理脚本..."
        
        # 执行清理脚本，即使失败也继续执行
        if bash "${OTHERS_DIR}/cleanup.sh"; then
            log info "Kube-OVN 清理脚本执行成功"
        else
            log warning "Kube-OVN 清理脚本执行失败，但将继续执行后续清理步骤"
        fi
    else
        log warning "Kube-OVN 清理脚本不存在: ${OTHERS_DIR}/cleanup.sh"
        
        # 尝试使用 kubectl 手动清理 Kube-OVN 资源
        log info "尝试手动清理 Kube-OVN 资源..."
        
        # 删除 Kube-OVN 相关命名空间和资源
        kubectl delete ns kube-ovn &>/dev/null || true
        kubectl delete crd ips.kubeovn.io networks.kubeovn.io subnets.kubeovn.io &>/dev/null || true
        kubectl delete ds kube-ovn-cni -n kube-system &>/dev/null || true
        kubectl delete deployment ovn-central kube-ovn-controller -n kube-system &>/dev/null || true
    fi
    
    # 在所有节点上清理 Kube-OVN 相关文件和目录
    log info "清理 Kube-OVN 相关文件和目录..."
    
    # 使用 ansible 在所有节点上执行清理命令
    ansible -i "${INVENTORY}" all -m shell -a "
        rm -rf /var/run/openvswitch /var/run/ovn /etc/origin/openvswitch/ /etc/origin/ovn/ /etc/cni/net.d/00-kube-ovn.conflist /etc/cni/net.d/01-kube-ovn.conflist /var/log/openvswitch /var/log/ovn /var/log/kube-ovn 2>/dev/null || true
    " || log warning "清理 Kube-OVN 文件和目录失败，但将继续执行"
    
    log info "Kube-OVN 卸载完成"
    return 0
}

# 修改 destroy_kubernetes 函数，在卸载 Kubernetes 前先卸载 Kube-OVN
function destroy_kubernetes() {
    log info "开始卸载 Kubernetes 集群，inventory: $INVENTORY"
    
    # 先卸载 Kube-OVN
    uninstall_kube_ovn
    
    # 然后卸载 Kubernetes 集群
    ${KUBEZ_ANSIBLE_CMD} destroy --yes-i-really-really-mean-it || { 
        log error "卸载 Kubernetes 集群失败"; 
        exit 1; 
    }
    log info "Kubernetes 集群卸载完成"
}

# 添加安装选项验证函数
#function validate_install_option() {
#    local option="$1"
#    local valid_options=("all" "harbor" "monitoring" "univirt" "check_and_upload" "test" "crossplane" "volcano")
#
#    for valid_option in "${valid_options[@]}"; do
#        if [ "$option" = "$valid_option" ]; then
#            return 0
#        fi
#    done
#
#    log error "无效的安装选项: $option"
#    echo "有效的安装选项包括: ${valid_options[*]}"
#    return 1
#}
#
## 在 main 函数调用前添加参数验证
#if [ "$1" = "install" ]; then
#    if [ -z "$2" ]; then
#        log error "请指定安装选项"
#        show_help
#        exit 1
#    fi
#    validate_install_option "$2" || exit 1
#fi

# 执行主程序
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

