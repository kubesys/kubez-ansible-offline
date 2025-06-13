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
    BEGIN {
        in_containers = 0
        current_name = ""
        current_image = ""
        item_content_indent_level = -1 # Expected indent level for lines within a container item
    }

    # Detect "containers:" block
    /^[[:space:]]*containers:[[:space:]]*$/ {
        in_containers = 1
        current_name = ""
        current_image = ""
        item_content_indent_level = -1
        next
    }

    # Detect end of "containers:" block (e.g., a new key not indented further, or "---")
    in_containers && (!/^[[:space:]]+.*/ || $0 ~ /^---/) {
        if (current_name != "" && current_image != "") {
            print current_name "=" current_image
        }
        in_containers = 0
        current_name = ""
        current_image = ""
        item_content_indent_level = -1
        # If line is "---", awk handles it. If other non-indented line, it is processed after this block.
    }

    in_containers {
        # Current line being processed
        line = $0

        # Check for the start of a new container item: line starts with "- "
        if (match(line, /^[[:space:]]*-[[:space:]]/)) {
            # Output previously collected items data
            if (current_name != "" && current_image != "") {
                print current_name "=" current_image
            }
            # Reset for the new item
            current_name = ""
            current_image = ""

            # Determine the expected indent level for content lines of this item.
            # It is the indent of the line itself, plus the length of "- ", plus indent of actual content.
            match(line, /^([[:space:]]*-[[:space:]]+)/) # Matches literal "- " and its leading spaces
            prefix_len = RLENGTH

            temp_item_line = substr(line, prefix_len + 1) # Get content after "- "
            match(temp_item_line, /^([[:space:]]*)縈/) # Find leading spaces of content
            content_indent_len = RLENGTH
            item_content_indent_level = prefix_len + content_indent_len

            # Check if name or image is on this first line of the item
            if (match(line, /name:[[:space:]]*([^[:space:]]+)/)) {
                # RSTART and RLENGTH are for the whole regex match "name: value"
                # We need the captured group. For POSIX, extract the value part.
                name_val_substr = substr(line, RSTART) # Substring from "name:"
                if (match(name_val_substr, /:[[:space:]]*([^[:space:]]+)/)) { # Match ": value"
                     current_name = substr(name_val_substr, RSTART + 1, RLENGTH -1) # Get value, +1 to skip ":"
                     # Trim leading space if any from value itself if regex allows it like `:[[:space:]]*`
                     sub(/^[[:space:]]+/, "", current_name)
                }
            }
            if (match(line, /image:[[:space:]]*([^[:space:]]+)/)) {
                image_val_substr = substr(line, RSTART)
                if (match(image_val_substr, /:[[:space:]]*([^[:space:]]+)/)) {
                    current_image = substr(image_val_substr, RSTART + 1, RLENGTH - 1)
                    sub(/^[[:space:]]+/, "", current_image)
                }
            }
        } else if (item_content_indent_level != -1) { # Subsequent line of a container item
            match(line, /^([[:space:]]*)/)
            current_line_actual_indent = RLENGTH

            # Check if this line is indented as part of the current items content
            if (current_line_actual_indent >= item_content_indent_level) {
                 if (current_name == "" && match(line, /name:[[:space:]]*([^[:space:]]+)/)) {
                    name_val_substr = substr(line, RSTART)
                    if (match(name_val_substr, /:[[:space:]]*([^[:space:]]+)/)) {
                        current_name = substr(name_val_substr, RSTART + 1, RLENGTH - 1)
                        sub(/^[[:space:]]+/, "", current_name)
                    }
                }
                if (current_image == "" && match(line, /image:[[:space:]]*([^[:space:]]+)/)) {
                    image_val_substr = substr(line, RSTART)
                    if (match(image_val_substr, /:[[:space:]]*([^[:space:]]+)/)) {
                        current_image = substr(image_val_substr, RSTART + 1, RLENGTH - 1)
                        sub(/^[[:space:]]+/, "", current_image)
                    }
                }
            } else { # Line is less indented than current items content, so current item effectively ends.
                if (current_name != "" && current_image != "") {
                     print current_name "=" current_image
                }
                current_name = ""
                current_image = ""
                item_content_indent_level = -1
                # This line will be re-evaluated in the next awk cycle against all rules.
                # To prevent it from being consumed by next at the end of in_containers block,
                # we should not use next if we want this line to be reprocessed.
                # However, the current structure with next at the end of in_containers means
                # this line will be consumed. For this specific logic, it is okay,
                # as a less-indented line correctly signifies end of current item.
            }
        }
        next # Consume lines processed by in_containers logic
    }

    # Lines not consumed by in_containers logic (e.g. before containers: or after block ends)
    # are implicitly printed if there was a `print $0` here, or just processed by other rules.
    # This functions specific job is extraction, so no default print $0.

    END {
        # After all lines processed, if there is a pending item, print it.
        if (current_name != "" && current_image != "") {
            print current_name "=" current_image
        }
    }
'

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
        modify_namespace = (ENVIRON["new_ns"] != "")
        modify_pull_policy = (ENVIRON["pull_policy"] != "")

        # Variables for handling container items
        in_containers_block = 0
        current_item_lines = "" # Buffer for lines of the current container item
        current_item_name = ""
        current_item_image_line = ""
        current_item_image_original = ""
        current_item_image_indent = ""
        item_start_indent_level = -1 # Indent level of the line starting with "- "
    }
    {
        # Handle namespace modifications (these are global or metadata-level)
        if (modify_namespace) {
            if ($0 ~ /^[[:space:]]*namespace:[[:space:]]*/) {
                sub(/:.*/, ": " ENVIRON["new_ns"], $0)
            }
            if (ENVIRON["old_ns"] != "") {
                gsub(ENVIRON["old_ns"], ENVIRON["new_ns"], $0)
            }
        }

        # Detect entering/leaving containers block
        if (/^[[:space:]]*containers:[[:space:]]*$/) {
            in_containers_block = 1
            print $0
            next
        }
        # Heuristic for exiting containers block: line not indented under spec/template/jobTemplate or new top-level key
        if (in_containers_block && (!/^[[:space:]]+.*/ || $0 ~ /^---/)) {
            # Process any pending container item before exiting
            if (item_start_indent_level != -1) {
                process_pending_container_item()
            }
            in_containers_block = 0
            # Fall through to print current line if it is not "---"
        }

        if (in_containers_block) {
            match($0, /^([[:space:]]*)-[[:space:]]/);
            # Restore original logic for line_starts_with_dash_at_indent
            if (RLENGTH > 0) {
                line_starts_with_dash_at_indent = length(substr($0,1,RLENGTH-1));
            } else {
                line_starts_with_dash_at_indent = -1;
            }

            # Restructure the if/else if/else
            processed_current_line = 0;

            if (line_starts_with_dash_at_indent != -1) {
                if (item_start_indent_level != -1) {
                    process_pending_container_item();
                }
                item_start_indent_level = line_starts_with_dash_at_indent;
                current_item_lines = $0 "\n";
                extract_name_image_from_line($0);
                processed_current_line = 1;
            }

            if (processed_current_line == 0 && item_start_indent_level != -1) { # Equivalent to else if
                match($0, /^([[:space:]]*)/);
                current_line_indent = RLENGTH;
                if (current_line_indent > item_start_indent_level || ($0 ~ /imagePullPolicy:/ && current_item_image_line != "")) {
                    current_item_lines = current_item_lines $0 "\n";
                    extract_name_image_from_line($0);
                } else {
                    process_pending_container_item();
                    print $0;
                }
                processed_current_line = 1;
            }

            if (processed_current_line == 0) { # Equivalent to else
                print $0;
            }
            next;
        }

        # Default print for lines not handled by above logic (e.g. outside containers block)
        print $0
    }
    END {
        # Process any final pending container item
        if (item_start_indent_level != -1) {
            process_pending_container_item()
        }
    }

    # Helper function to extract name and image from a line
    function extract_name_image_from_line(line) {
        # For name
        temp_line_for_name = line
        # Try to match and extract name. Regex: find "name:" then capture non-space chars.
        if (sub(/.*name:[[:space:]]*/, "", temp_line_for_name)) { # Remove everything up to "name: "
            sub(/[[:space:]].*/, "", temp_line_for_name) # Remove everything after the name value
            if (current_item_name == "") current_item_name = temp_line_for_name
        }

        # For image
        temp_line_for_image = line
        # Try to match and extract image. Regex: find "image:" then capture non-space chars.
        if (sub(/.*image:[[:space:]]*/, "", temp_line_for_image)) { # Remove everything up to "image: "
            sub(/[[:space:]].*/, "", temp_line_for_image) # Remove everything after the image value
            if (current_item_image_line == "") {
                current_item_image_line = line # Store the original full line
                current_item_image_original = temp_line_for_image # Store the extracted image value

                # Get indent for image line
                match(line, /^([[:space:]]*)/) # This match is fine, it sets RSTART/RLENGTH
                current_item_image_indent = substr(line, 1, RLENGTH)
            }
        }
    }

    # Helper function to process the buffered container item
    function process_pending_container_item() {
        if (current_item_name == "" && current_item_image_line == "") { # Nothing to process
            printf "%s", current_item_lines; # Print whatever was buffered (e.g. comments)
            reset_item_state();
            return;
        }

        effective_container_name_for_lookup = current_item_name
        gsub(/-/, "_", effective_container_name_for_lookup) # Normalize name for env var lookup

        final_image_to_use = ""
        if (effective_container_name_for_lookup != "" && ENVIRON[effective_container_name_for_lookup "_final_img"] != "") {
            final_image_to_use = ENVIRON[effective_container_name_for_lookup "_final_img"]
        }

        # Reconstruct and print the items lines
        split(current_item_lines, lines_array, "\n") # Corrected from item_lines to current_item_lines
        item_image_line_modified = 0
        image_line_printed_with_policy = 0

        for (i = 1; i < length(lines_array); i++) {
            line_to_print = lines_array[i]
            is_image_line = (lines_array[i] == current_item_image_line && current_item_image_line != "")

            if (is_image_line) {
                if (final_image_to_use != "") {
                    sub(current_item_image_original, final_image_to_use, line_to_print)
                }
                print line_to_print
                item_image_line_modified = (final_image_to_use != "" && final_image_to_use != current_item_image_original)

                if (modify_pull_policy) {
                    # Check if next line is pull policy
                    next_line_is_policy = ( (i+1) < length(lines_array) && lines_array[i+1] ~ /[[:space:]]*imagePullPolicy:[[:space:]]*/)
                    if (!next_line_is_policy) {
                        print current_item_image_indent "imagePullPolicy: " ENVIRON["pull_policy"]
                    }
                    # if next line IS policy, it will be handled in the next iteration
                }
                image_line_printed_with_policy = 1 # Mark that logic for policy insertion around image line is done
            } else if (modify_pull_policy && lines_array[i] ~ /[[:space:]]*imagePullPolicy:[[:space:]]*/) {
                # This line is an existing imagePullPolicy
                # If it followed our processed image line, or if no specific image line was targeted but we need to change policy
                if (image_line_printed_with_policy || current_item_image_line == "") {
                     print current_item_image_indent "imagePullPolicy: " ENVIRON["pull_policy"]
                } else {
                     print line_to_print # Print existing policy if it is not related to the image we processed
                }
            } else {
                print line_to_print
            }
        }

        # If no image line was found in item, but we need to add pull policy (e.g. for safety, though unusual)
        if (modify_pull_policy && current_item_image_line == "" && item_start_indent_level != -1) {
             # This case is tricky: where to add it if no image line?
             # For now, assume policy is only added/modified if an image line exists or policy itself exists.
        }

        reset_item_state()
    }

    function reset_item_state() {
        current_item_lines = ""
        current_item_name = ""
        current_item_image_line = ""
        current_item_image_original = ""
        current_item_image_indent = ""
        item_start_indent_level = -1 # Crucial to reset
    }
'

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