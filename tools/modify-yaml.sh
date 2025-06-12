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

# modify_volcano_monitoring_yaml.sh
# 用于修改 Volcano 监控组件 YAML 文件的脚本

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

# 生成自动输出文件名
function generate_output_filename() {
    local input_file="$1"
    local namespace="$2"

    # 获取输入文件的目录和基础名称
    local input_dir=$(dirname "$input_file")
    local input_basename=$(basename "$input_file")
    local input_name="${input_basename%.*}"
    local input_ext="${input_basename##*.}"

    # 生成时间戳
    local timestamp=$(date '+%Y%m%d%H%M%S')

    # 构建输出文件名
    local output_filename="${input_name}-modified-${namespace}-${timestamp}.${input_ext}"
    local output_path="${input_dir}/${output_filename}"

    echo "$output_path"
}

# 显示帮助信息
function show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --input FILE           输入的原始 YAML 文件路径 (必需)"
    echo "  -o, --output FILE          输出的修改后 YAML 文件路径 (可选，自动生成)"
    echo "  -n, --namespace NAME       目标命名空间 (默认: volcano-monitoring)"
    echo "  -r, --pull-policy POLICY  镜像拉取策略 (默认: IfNotPresent)"
    echo "  --<containername>-img IMG  指定容器镜像 (如: --prometheus-img prom/prometheus:latest)"
    echo "  --<containername>-version VER 指定容器镜像版本 (如: --prometheus-version v2.48.1)"
    echo "  -h, --help                 显示此帮助信息"
    echo ""
    echo "支持的容器名称:"
    echo "  prometheus, grafana, kube-state-metrics"
    echo ""
    echo "注意:"
    echo "  - 如果不指定 -o 参数，将自动生成输出文件名"
    echo "  - 输出文件名格式: <输入文件名>-modified-<命名空间>-<时间戳>.yaml"
    echo ""
    echo "示例:"
    echo "  $0 -i volcano-monitoring.yaml \\"
    echo "     --prometheus-img prom/prometheus:latest --grafana-img grafana/grafana:latest"
    echo ""
    echo "  $0 -i volcano-monitoring.yaml -o custom-output.yaml \\"
    echo "     --prometheus-version v2.50.0 --grafana-version 10.0.0"
    echo ""
    echo "  $0 -i volcano-monitoring.yaml -n my-monitoring \\"
    echo "     --prometheus-img prom/prometheus --prometheus-version v2.50.0 \\"
    echo "     --grafana-img grafana/grafana --grafana-version 10.0.0"
}

# 解析镜像名称和版本
function parse_image_info() {
    local image_full="$1"
    local image_name=""
    local image_version=""

    if [[ "$image_full" =~ ^(.+):(.+)$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        image_version="${BASH_REMATCH[2]}"
    else
        image_name="$image_full"
        image_version=""
    fi

    echo "$image_name|$image_version"
}

# 构建完整镜像名称
function build_image_name() {
    local base_name="$1"
    local version="$2"

    if [[ -n "$version" ]]; then
        echo "${base_name}:${version}"
    else
        echo "$base_name"
    fi
}
# 主要的 YAML 修改函数
function modify_volcano_monitoring_yaml() {
    local input_file="$1"
    local output_file="$2"
    local namespace="$3"
    local image_pull_policy="$4"
    shift 4

    # 解析镜像配置参数
    declare -A container_images
    declare -A container_versions

    while [[ $# -gt 0 ]]; do
        case $1 in
            --*-img)
                local container_name=$(echo "$1" | sed 's/^--\(.*\)-img$/\1/' | tr '-' '_')
                container_images["$container_name"]="$2"
                shift 2
                ;;
            --*-version)
                local container_name=$(echo "$1" | sed 's/^--\(.*\)-version$/\1/' | tr '-' '_')
                container_versions["$container_name"]="$2"
                shift 2
                ;;
            *)
                log warning "未知参数: $1"
                shift
                ;;
        esac
    done

    # 参数验证
    if [[ -z "$input_file" || -z "$namespace" || -z "$image_pull_policy" ]]; then
        log error "缺少必需参数"
        show_help
        return 1
    fi

    # 检查输入文件是否存在
    if [[ ! -f "$input_file" ]]; then
        log error "输入文件不存在: $input_file"
        return 1
    fi

    # 如果没有提供输出文件名，自动生成
    if [[ -z "$output_file" ]]; then
        output_file=$(generate_output_filename "$input_file" "$namespace")
        log info "自动生成输出文件名: $output_file"
    fi

    log info "开始修改 Volcano 监控 YAML 文件..."
    log info "输入文件: $input_file"
    log info "输出文件: $output_file"
    log info "目标命名空间: $namespace"
    log info "镜像拉取策略: $image_pull_policy"

    # 显示镜像配置
    for container in "${!container_images[@]}"; do
        log info "容器 $container 镜像: ${container_images[$container]}"
    done
    for container in "${!container_versions[@]}"; do
        log info "容器 $container 版本: ${container_versions[$container]}"
    done

    # 提取旧namespace
    local old_namespace=$(grep -E "^\s*namespace:\s*" "$input_file" | head -1 | awk '{print $2}')
    if [[ -z "$old_namespace" ]]; then
        log error "无法从 YAML 中检测 namespace"
        return 1
    fi
    log info "检测到旧 namespace: $old_namespace"

    # 创建临时文件
    local temp_file="${output_file}.tmp"

    # 构建 awk 脚本参数
    local awk_args=()
    awk_args+=(-v old_ns="$old_namespace")
    awk_args+=(-v new_ns="$namespace")
    awk_args+=(-v pull_policy="$image_pull_policy")

    # 添加镜像配置到 awk 参数
    for container in "${!container_images[@]}"; do
        awk_args+=(-v "${container}_img=${container_images[$container]}")
    done
    for container in "${!container_versions[@]}"; do
        awk_args+=(-v "${container}_version=${container_versions[$container]}")
    done

    # 使用 awk 进行字符串替换
    log info "执行主要字符串替换..."
    if ! awk "${awk_args[@]}" '
    BEGIN {
        # 定义容器名称映射
        container_patterns["prometheus"] = "prom/prometheus"
        container_patterns["grafana"] = "grafana/grafana"
        container_patterns["kube_state_metrics"] = "docker\\.io/volcanosh/kube-state-metrics"
    }
    {
        line = $0

        # 替换命名空间
        if (match(line, /^[[:space:]]*namespace:[[:space:]]*/) && index(line, old_ns)) {
            sub(/namespace:[[:space:]]*[^[:space:]]*/, "namespace: " new_ns, line)
        }

        # 替换镜像
        if (match(line, /^[[:space:]]*image:[[:space:]]*/)) {
            for (container in container_patterns) {
                pattern = container_patterns[container]
                img_var = container "_img"
                version_var = container "_version"

                if (match(line, "image:[[:space:]]*" pattern)) {
                    new_image = ""

                    # 如果没有完整镜像名称，但有版本号，则构建镜像名称
                    if (new_image == "") {
                        base_image = ""
                        version = ""

                        if (version_var == "prometheus_version" && prometheus_version != "") {
                            base_image = "prom/prometheus"
                            version = prometheus_version
                        } else if (version_var == "grafana_version" && grafana_version != "") {
                            base_image = "grafana/grafana"
                            version = grafana_version
                        } else if (version_var == "kube_state_metrics_version" && kube_state_metrics_version != "") {
                            base_image = "docker.io/volcanosh/kube-state-metrics"
                            version = kube_state_metrics_version
                        }

                        if (base_image != "" && version != "") {
                            new_image = base_image ":" version
                        }
                    }

                    # 如果有新镜像名称，则替换
                    if (new_image != "") {
                        sub(/image:[[:space:]]*[^[:space:]]*/, "image: " new_image, line)
                    }
                }
            }
        }

        # 替换 imagePullPolicy
        if (match(line, /^[[:space:]]*imagePullPolicy:[[:space:]]*/)) {
            sub(/imagePullPolicy:[[:space:]]*[^[:space:]]*/, "imagePullPolicy: " pull_policy, line)
        }

        # 替换服务引用中的命名空间
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
    }' "$input_file" > "$temp_file"; then
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
    ' "$temp_file" > "$output_file"; then
        log error "imagePullPolicy 处理失败"
        rm -f "$temp_file"
        return 1
    fi

    # 清理临时文件
    rm -f "$temp_file"

    # 验证生成的文件
    if [[ ! -f "$output_file" ]]; then
        log error "修改后的 YAML 文件生成失败"
        return 1
    fi

    # 检查文件是否为空
    if [[ ! -s "$output_file" ]]; then
        log error "修改后的 YAML 文件为空"
        rm -f "$output_file"
        return 1
    fi

    log info "YAML 文件修改完成: $output_file"
    log info "修改摘要:"
    log info "  命名空间: $old_namespace -> $namespace"
    for container in "${!container_images[@]}"; do
        log info "  容器 $container 镜像: ${container_images[$container]}"
    done
    for container in "${!container_versions[@]}"; do
        log info "  容器 $container 版本: ${container_versions[$container]}"
    done
    log info "  镜像拉取策略: $image_pull_policy"
    return 0
}

# 主函数
function main() {
    # 设置默认值
    local input_file=""
    local output_file=""
    local namespace="volcano-monitoring"
    local image_pull_policy="IfNotPresent"

    # 存储镜像相关参数
    local image_args=()

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            -r|--pull-policy)
                image_pull_policy="$2"
                shift 2
                ;;
            --*-img|--*-version)
                image_args+=("$1" "$2")
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 检查必需参数
    if [[ -z "$input_file" ]]; then
        log error "缺少输入文件参数 (-i|--input)"
        show_help
        exit 1
    fi

    # 调用主要的修改函数
    modify_volcano_monitoring_yaml "$input_file" "$output_file" "$namespace" "$image_pull_policy" "${image_args[@]}"
}

# 执行主程序
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi