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

# 打印日志函数
function log() {
    local caller_info=$(caller 0)
    local line_number=$(echo "$caller_info" | awk '{print $1}')
    local file_name=$(basename $(echo "$caller_info" | awk '{print $2}'))
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

    local input_dir=$(dirname "$input_file")
    local input_basename=$(basename "$input_file")
    local input_name="${input_basename%.*}"
    local input_ext="${input_basename##*.}"
    local timestamp=$(date '+%Y%m%d%H%M%S')

#    if [[ -n "$namespace" ]]; then
#        local output_filename="${input_name}-modified-${namespace}-${timestamp}.${input_ext}"
#    else
#        local output_filename="${input_name}-modified-${timestamp}.${input_ext}"
#    fi
    local output_filename="${input_name}-${timestamp}.${input_ext}"

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
    echo "  -n, --namespace NAME       目标命名空间 (可选，不设置则不修改命名空间)"
    echo "  -r, --pull-policy POLICY  镜像拉取策略 (可选，不设置则不修改策略)"
    echo "  --<container>-img IMAGE    指定容器镜像，支持以下格式:"
    echo "                             - library/image (只修改镜像名，保持原版本)"
    echo "                             - library/image:version (修改镜像名和版本)"
    echo "  --<container>-ver VERSION  指定容器镜像版本，会覆盖 --<container>-img 中的版本"
    echo "  --image NAME=IMAGE_URI     覆盖指定容器的完整镜像 (例如: --image prometheus=prom/prometheus:v2.48.1)"
    echo "                             NAME 是容器名称, IMAGE_URI 是完整镜像字符串"
    echo "                             可以多次指定此参数"
    echo "  -h, --help                 显示此帮助信息"
    echo ""
    echo "注意:"
    echo "  - 脚本会自动从 YAML 文件中提取现有的容器镜像信息"
    echo "  - 支持任意容器名称，不限于预定义列表"
    echo "  - 参数优先级: --image > --<container>-ver > --<container>-img"
    echo "  - 如果只提供 --<container>-ver，会查找 YAML 中对应容器的镜像名进行版本替换"
    echo "  - 命名空间和镜像拉取策略都是可选的，不设置则不修改"
    echo ""
    echo "示例:"
    echo "  # 只修改镜像，不改命名空间和拉取策略"
    echo "  $0 -i input.yaml --prometheus-img prom/prometheus"
    echo ""
    echo "  # 修改镜像名和版本"
    echo "  $0 -i input.yaml --prometheus-img prom/prometheus:v2.50.0"
    echo ""
    echo "  # 同时修改命名空间和镜像"
    echo "  $0 -i input.yaml -n my-namespace --prometheus-img prom/prometheus:v2.50.0"
    echo ""
    echo "  # 只修改拉取策略"
    echo "  $0 -i input.yaml -r Always"
    echo ""
    echo "  # 先设置镜像，再用版本参数覆盖版本"
    echo "  $0 -i input.yaml --prometheus-img prom/prometheus:v2.45.0 --prometheus-ver v2.50.0"
    echo ""
    echo "  # 只修改版本，保持原镜像名"
    echo "  $0 -i input.yaml --prometheus-ver v2.50.0"
    echo ""
    echo "  # 使用完整镜像URI"
    echo "  $0 -i input.yaml --image prometheus=prom/prometheus:v2.50.0"
    echo ""
    echo "  # 混合使用多种参数"
    echo "  $0 -i input.yaml -n production -r IfNotPresent \\"
    echo "     --prometheus-img prom/prometheus:v2.45.0 --prometheus-ver v2.50.0 \\"
    echo "     --grafana-ver 10.0.0 \\"
    echo "     --image alertmanager=prom/alertmanager:v0.25.0"
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

# 从YAML文件中提取现有的容器镜像信息
function extract_existing_images() {
    local input_file="$1"
    declare -A existing_images

    # 使用awk提取所有image行及其上下文
    local awk_extract='
    {
        # 查找image行
        if ($0 ~ /^[[:space:]]*image:[[:space:]]*/) {
            # 提取镜像名称
            match($0, /image:[[:space:]]*([^[:space:]]+)/, arr)
            if (arr[1]) {
                images[NR] = arr[1]
            }
        }
        # 查找容器名称（在image行之前）
        if ($0 ~ /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ || $0 ~ /^[[:space:]]*name:[[:space:]]*/) {
            match($0, /name:[[:space:]]*([^[:space:]]+)/, arr)
            if (arr[1]) {
                container_names[NR] = arr[1]
            }
        }
    }
    END {
        # 匹配容器名和镜像
        for (img_line in images) {
            closest_name_line = 0
            closest_name = ""
            # 查找最近的容器名
            for (name_line in container_names) {
                if (name_line < img_line && name_line > closest_name_line) {
                    closest_name_line = name_line
                    closest_name = container_names[name_line]
                }
            }
            if (closest_name != "") {
                print closest_name "=" images[img_line]
            }
        }
    }'

    # 执行提取并解析结果
    local extraction_result=$(awk "$awk_extract" "$input_file")

    # 解析提取结果到关联数组
    while IFS='=' read -r container_name image_uri; do
        if [[ -n "$container_name" && -n "$image_uri" ]]; then
            # 标准化容器名（将-替换为_）
            local normalized_name=$(echo "$container_name" | tr '-' '_')
            existing_images["$normalized_name"]="$image_uri"
            log info "从YAML中提取到容器 $container_name 的现有镜像: $image_uri"
        fi
    done <<< "$extraction_result"

    # 将关联数组转换为全局变量（bash 3兼容）
    for container in "${!existing_images[@]}"; do
        eval "EXISTING_IMAGE_${container}='${existing_images[$container]}'"
    done
}

# 获取现有镜像信息
function get_existing_image() {
    local container_name="$1"
    local normalized_name=$(echo "$container_name" | tr '-' '_')
    local var_name="EXISTING_IMAGE_${normalized_name}"
    echo "${!var_name}"
}

# 主要的 YAML 修改函数
function modify_volcano_monitoring_yaml() {
    local input_file="$1"
    local output_file="$2"
    local namespace="$3"
    local image_pull_policy="$4"
    shift 4

    declare -A container_images
    declare -A container_versions
    declare -A container_full_images
    declare -A final_images

    # 首先提取现有镜像信息
    extract_existing_images "$input_file"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --*-img)
                local container_name=$(echo "$1" | sed 's/^--\(.*\)-img$/\1/' | tr '-' '_')
                local image_input="$2"

                container_images["$container_name"]="$image_input"
                log info "设置容器 $container_name 镜像: $image_input"
                shift 2
                ;;
            --*-ver)
                local container_name=$(echo "$1" | sed 's/^--\(.*\)-ver$/\1/' | tr '-' '_')
                container_versions["$container_name"]="$2"
                log info "设置容器 $container_name 版本: $2"
                shift 2
                ;;
            --image)
                if [[ "$2" =~ ^([^=]+)=(.+)$ ]]; then
                    local container_name="${BASH_REMATCH[1]}"
                    local full_image="${BASH_REMATCH[2]}"
                    container_name=$(echo "$container_name" | tr '-' '_')
                    container_full_images["$container_name"]="$full_image"
                    log info "设置容器 $container_name 完整镜像: $full_image"
                else
                    log error "无效的 --image 参数格式: $2"
                    log error "正确格式: --image NAME=IMAGE_URI"
                    return 1
                fi
                shift 2
                ;;
            *)
                log warning "未知参数: $1"
                shift
                ;;
        esac
    done

    # 构建最终镜像映射
    # 1. 优先级最高：--image 参数
    for container in "${!container_full_images[@]}"; do
        final_images["$container"]="${container_full_images[$container]}"
        log info "优先级1 -> 容器 $container 使用完整镜像: ${final_images[$container]}"
    done

    # 2. 处理 --<container>-img 参数
    for container in "${!container_images[@]}"; do
        # 如果已经通过 --image 设置了，则跳过
        if [[ -n "${final_images[$container]}" ]]; then
            continue
        fi

        local input_image="${container_images[$container]}"
        local parsed_info=$(parse_image_info "$input_image")
        local base_image=$(echo "$parsed_info" | cut -d'|' -f1)
        local image_version=$(echo "$parsed_info" | cut -d'|' -f2)

        # 如果--<container>-img包含版本，使用该版本
        if [[ -n "$image_version" ]]; then
            final_images["$container"]="$input_image"
            log info "优先级2a -> 容器 $container 使用镜像（含版本）: ${final_images[$container]}"
        else
            # 如果没有版本，保持原有版本或使用空版本
            local existing_image=$(get_existing_image "$container")
            if [[ -n "$existing_image" ]]; then
                local existing_parsed=$(parse_image_info "$existing_image")
                local existing_version=$(echo "$existing_parsed" | cut -d'|' -f2)
                final_images["$container"]=$(build_image_name "$base_image" "$existing_version")
                log info "优先级2b -> 容器 $container 使用新镜像名+原版本: ${final_images[$container]}"
            else
                final_images["$container"]="$base_image"
                log info "优先级2c -> 容器 $container 使用镜像名（无版本）: ${final_images[$container]}"
            fi
        fi
    done

    # 3. 处理 --<container>-ver 参数（会覆盖之前的版本设置）
    for container in "${!container_versions[@]}"; do
        local new_version="${container_versions[$container]}"

        if [[ -n "${final_images[$container]}" ]]; then
            # 已有镜像设置，更新版本
            local current_parsed=$(parse_image_info "${final_images[$container]}")
            local current_base=$(echo "$current_parsed" | cut -d'|' -f1)
            final_images["$container"]=$(build_image_name "$current_base" "$new_version")
            log info "优先级3a -> 容器 $container 版本覆盖: ${final_images[$container]}"
        else
            # 没有镜像设置，尝试从现有YAML中获取镜像名
            local existing_image=$(get_existing_image "$container")
            if [[ -n "$existing_image" ]]; then
                local existing_parsed=$(parse_image_info "$existing_image")
                local existing_base=$(echo "$existing_parsed" | cut -d'|' -f1)
                final_images["$container"]=$(build_image_name "$existing_base" "$new_version")
                log info "优先级3b -> 容器 $container 使用原镜像名+新版本: ${final_images[$container]}"
            else
                log warning "容器 $container 未找到现有镜像信息，无法仅通过版本进行修改"
            fi
        fi
    done

    if [[ -z "$input_file" ]]; then
        log error "缺少输入文件参数"
        show_help
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log error "输入文件不存在: $input_file"
        return 1
    fi

    # 检查是否有任何修改需要执行
    local has_changes=0
    if [[ -n "$namespace" ]]; then
        has_changes=1
    fi
    if [[ -n "$image_pull_policy" ]]; then
        has_changes=1
    fi
    if [[ ${#final_images[@]} -gt 0 ]]; then
        has_changes=1
    fi

    if [[ $has_changes -eq 0 ]]; then
        log warning "没有指定任何修改操作（命名空间、镜像拉取策略或容器镜像）"
        log info "将创建原文件的副本"
    fi

    if [[ -z "$output_file" ]]; then
        output_file=$(generate_output_filename "$input_file" "$namespace")
        log info "自动生成输出文件名: $output_file"
    fi

    log info "开始修改 YAML 文件..."
    log info "输入文件: $input_file"
    log info "输出文件: $output_file"

    if [[ -n "$namespace" ]]; then
        log info "目标命名空间: $namespace"
    else
        log info "命名空间: 不修改"
    fi

    if [[ -n "$image_pull_policy" ]]; then
        log info "镜像拉取策略: $image_pull_policy"
    else
        log info "镜像拉取策略: 不修改"
    fi

    if [[ ${#final_images[@]} -eq 0 ]]; then
        log info "容器镜像: 不修改"
    else
        log info "=== 最终镜像修改列表 ==="
        for container in "${!final_images[@]}"; do
            log info "容器 ${container} => ${final_images[$container]}"
        done
        log info "=========================="
    fi

    local old_namespace=""
    if [[ -n "$namespace" ]]; then
        old_namespace=$(grep -m 1 -E "^\s*namespace:\s*" "$input_file" | awk '{print $2}')
        if [[ -z "$old_namespace" ]]; then
            log warning "无法从 YAML 中自动检测到旧的 namespace"
        fi
        log info "检测到旧 namespace: ${old_namespace:-'未检测到'}"
    fi

    # 构建AWK脚本
    local awk_script='
    BEGIN {
        insert_policy_after_this_line = 0
        indent_for_policy = ""
        current_container = ""
        modify_namespace = (ENVIRON["new_ns"] != "")
        modify_pull_policy = (ENVIRON["pull_policy"] != "")
    }
    {
        # 1. 替换 metadata.namespace (仅当设置了新namespace时)
        if (modify_namespace && $0 ~ /^[[:space:]]*namespace:[[:space:]]*/) {
            sub(/:.*/, ": " ENVIRON["new_ns"], $0)
        }

        # 2. 全局替换硬编码的旧命名空间字符串 (仅当设置了新namespace时)
        if (modify_namespace && ENVIRON["old_ns"] != "") {
            gsub(ENVIRON["old_ns"], ENVIRON["new_ns"], $0)
        }

        # 3. 检测当前容器名
        if ($0 ~ /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ || $0 ~ /^[[:space:]]*name:[[:space:]]*/) {
            match($0, /name:[[:space:]]*([^[:space:]]+)/, arr)
            if (arr[1]) {
                current_container = arr[1]
                gsub(/-/, "_", current_container)
            }
        }

        # 4. 替换镜像
        if ($0 ~ /^[[:space:]]*image:[[:space:]]*/) {
            match($0, /^([[:space:]]*)/)
            indent_for_policy = substr($0, 1, RLENGTH)

            # 检查当前容器是否需要替换镜像
            env_var = current_container "_final_img"
            if (ENVIRON[env_var] != "") {
                sub(/image:[[:space:]]*[^[:space:]]*/, "image: " ENVIRON[env_var], $0)
                print $0
                # 标记需要处理 imagePullPolicy (仅当设置了拉取策略时)
                if (modify_pull_policy) {
                    insert_policy_after_this_line = 1
                }
                next
            } else {
                print $0
                # 即使没有修改镜像，如果设置了拉取策略，也可能需要添加/修改策略
                if (modify_pull_policy) {
                    insert_policy_after_this_line = 1
                }
                next
            }
        }

        # 5. 修改或添加 imagePullPolicy (仅当设置了拉取策略时)
        if (insert_policy_after_this_line == 1) {
            if ($0 ~ /^[[:space:]]*imagePullPolicy:[[:space:]]*/) {
                # 如果当前行是 imagePullPolicy，则修改它
                print indent_for_policy "imagePullPolicy: " ENVIRON["pull_policy"]
            } else {
                # 否则，插入新的 imagePullPolicy，然后打印当前行
                print indent_for_policy "imagePullPolicy: " ENVIRON["pull_policy"]
                print $0
            }
            insert_policy_after_this_line = 0
            next
        }

        print $0
    }'

    log info "执行 YAML 修改..."

    # 构建环境变量
    local env_vars=()
    env_vars+=("old_ns=$old_namespace")
    env_vars+=("new_ns=$namespace")
    env_vars+=("pull_policy=$image_pull_policy")

    # 添加所有容器的最终镜像到环境变量
    for container in "${!final_images[@]}"; do
        env_vars+=("${container}_final_img=${final_images[$container]}")
    done

    # 执行 AWK 处理
    if ! env "${env_vars[@]}" awk "$awk_script" "$input_file" > "$output_file"; then
        log error "AWK 脚本处理失败"
        return 1
    fi

    log info "YAML 文件修改成功: $output_file"
    return 0
}

# 主函数
function main() {
    local input_file=""
    local output_file=""
    local namespace=""
    local image_pull_policy=""
    local image_args=()

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
            --*-img|--*-ver)
                image_args+=("$1" "$2")
                shift 2
                ;;
            --image)
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

    if [[ -z "$input_file" ]]; then
        log error "缺少输入文件参数 (-i|--input)"
        show_help
        exit 1
    fi

    modify_volcano_monitoring_yaml "$input_file" "$output_file" "$namespace" "$image_pull_policy" "${image_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi