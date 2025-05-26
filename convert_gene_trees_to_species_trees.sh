#!/bin/bash

# Script to convert gene names to species names in tree files using a mapping file.

# --- Functions ---
print_usage() {
    echo "Usage: $0 <original_gene_tree_file> <original_bootstrap_list_file> <astral_mapping_file> <output_basename>"
    echo "  <original_gene_tree_file>: Path to the merged gene tree file (e.g., nc_best.trees)."
    echo "  <original_bootstrap_list_file>: Path to the file listing bootstrap tree files (e.g., nc_ml_boot.txt)."
    echo "  <astral_mapping_file>: Path to the ASTRAL mapping file (species: gene1,gene2,...)."
    echo "  <output_basename>: Basename for the output files (e.g., nc_species_mapped)."
    echo
    echo "Example: $0 nc_best.trees nc_ml_boot.txt astral_mapping.txt nc_species_mapped"
}

# --- Argument Parsing ---
if [ "$#" -ne 4 ]; then
    print_usage
    exit 1
fi

ORIGINAL_TREE_FILE="$1"
ORIGINAL_BOOTSTRAP_LIST_FILE="$2"
ASTRAL_MAPPING_FILE="$3"
OUTPUT_BASENAME="$4"

# --- Define Output Names ---
NEW_TREE_FILE="${OUTPUT_BASENAME}.tre"
NEW_BOOTSTRAP_DIR="${OUTPUT_BASENAME}_bootstraps"
NEW_BOOTSTRAP_LIST_FILE="${OUTPUT_BASENAME}_bootstraps.txt"

# --- Input Validation ---
for f in "$ORIGINAL_TREE_FILE" "$ORIGINAL_BOOTSTRAP_LIST_FILE" "$ASTRAL_MAPPING_FILE"; do
    if [ ! -f "$f" ]; then
        echo "错误: 输入文件 '$f' 未找到。" >&2
        print_usage
        exit 1
    fi
    if [ ! -r "$f" ]; then
        echo "错误: 输入文件 '$f' 没有读取权限。" >&2
        print_usage
        exit 1
    fi
done

# --- Create Output Directory ---
echo "INFO: 创建输出目录 '$NEW_BOOTSTRAP_DIR'..."
mkdir -p "$NEW_BOOTSTRAP_DIR"
if [ $? -ne 0 ]; then
    echo "错误: 无法创建输出目录 '$NEW_BOOTSTRAP_DIR'。" >&2
    exit 1
fi

# --- Prepare Mappings for sed ---
echo "INFO: 正在读取映射文件 '$ASTRAL_MAPPING_FILE'..."
declare -A gene_to_species_map # 需要 Bash 4+
processed_mappings=0

# 使用 while循环和IFS读取映射文件，确保正确处理包含空格的物种名和基因名
while IFS=':' read -r species_part genes_part || [[ -n "$species_part" ]]; do
    # 清理物种名两端的空格
    species_name=$(echo "$species_part" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # 如果 species_name 为空 (例如空行或格式错误的行)，则跳过
    if [ -z "$species_name" ]; then
        continue
    fi

    # 清理基因列表字符串两端的空格
    genes_list_str=$(echo "$genes_part" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 按逗号分割基因列表
    IFS=',' read -r -a gene_array <<< "$genes_list_str"
    for gene_leaf_raw in "${gene_array[@]}"; do
        # 清理单个基因叶节点名两端的空格
        gene_leaf=$(echo "$gene_leaf_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$gene_leaf" ]; then
            # 检查是否已存在映射且物种名不同
            if [[ -v gene_to_species_map["$gene_leaf"] && "${gene_to_species_map["$gene_leaf"]}" != "$species_name" ]]; then
                echo "警告: 基因 '$gene_leaf' 被映射到多个物种 ('${gene_to_species_map["$gene_leaf"]}' 和 '$species_name')。将使用后者: '$species_name'。" >&2
            fi
            gene_to_species_map["$gene_leaf"]="$species_name"
            processed_mappings=$((processed_mappings + 1))
        fi
    done
done < "$ASTRAL_MAPPING_FILE"


if [ "$processed_mappings" -eq 0 ]; then
    echo "警告: 在 '$ASTRAL_MAPPING_FILE' 中未找到有效的基因到物种的映射。输出的树文件可能保持不变。" >&2
fi
echo "INFO: 找到 $processed_mappings 个基因到物种的映射关系。"

sed_expressions=()
# 从关联数组构建sed表达式列表
# 不需要按长度排序键，因为 GENE 确保精确匹配整个基因名
for gene_leaf in "${!gene_to_species_map[@]}"; do
    species_name="${gene_to_species_map[$gene_leaf]}"
    # 转义 sed 分隔符 '~' (如果基因名或物种名中包含它)
    escaped_gene_leaf=$(printf '%s
' "$gene_leaf" | sed 's/[~]/\&/g')
    escaped_species_name=$(printf '%s
' "$species_name" | sed 's/[~]/\&/g')
    sed_expressions+=(-e "s~${escaped_gene_leaf}~${escaped_species_name}~g")
done

if [ ${#sed_expressions[@]} -eq 0 ]; then
    echo "警告: 未生成 sed 替换表达式。这意味着没有找到映射关系或映射关系处理失败。" >&2
    # 脚本仍会继续运行，但文件内容可能只是被复制
fi

# --- Function to Process a Tree File ---
process_tree_file() {
    local input_file="$1"
    local output_file="$2"

    if [ ! -f "$input_file" ]; then
        echo "错误: 输入树文件 '$input_file' 未找到。" >&2
        return 1
    fi

    # 仅当存在 sed 表达式时才执行替换
    if [ ${#sed_expressions[@]} -gt 0 ]; then
        sed "${sed_expressions[@]}" "$input_file" > "$output_file"
    else
        # 如果没有表达式，则复制文件以避免生成空文件
        cp "$input_file" "$output_file"
        echo "INFO: 没有基因名替换操作可执行；已将 '$input_file' 复制到 '$output_file'。" >&2
    fi

    if [ $? -ne 0 ]; then
        # 检查 sed 是否失败 (如果执行了)
        if [ ${#sed_expressions[@]} -gt 0 ]; then
             echo "错误: 处理树文件 '$input_file' 到 '$output_file' 失败 (sed 执行出错)。" >&2
        else # 检查 cp 是否失败
             echo "错误: 复制文件 '$input_file' 到 '$output_file' 失败。" >&2
        fi
        return 1
    fi
    return 0
}

# --- Process Main Tree File ---
echo "INFO: 正在处理主树文件 '$ORIGINAL_TREE_FILE' -> '$NEW_TREE_FILE'..."
process_tree_file "$ORIGINAL_TREE_FILE" "$NEW_TREE_FILE"
if [ $? -ne 0 ]; then
    echo "错误: 处理主树文件失败。正在退出。" >&2
    exit 1
fi

# --- Process Bootstrap Files ---
echo "INFO: 正在处理来自 '$ORIGINAL_BOOTSTRAP_LIST_FILE' 的 bootstrap 文件到目录 '$NEW_BOOTSTRAP_DIR'..."
# 清空或创建新的 bootstrap 列表文件
> "$NEW_BOOTSTRAP_LIST_FILE"

num_boot_processed=0
num_boot_failed=0
# 使用 while read 读取 bootstrap 文件列表
while IFS= read -r original_boot_file_path || [[ -n "$original_boot_file_path" ]]; do
    # 清理路径两端的空格
    original_boot_file_path_trimmed=$(echo "$original_boot_file_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # 跳过空行
    if [ -z "$original_boot_file_path_trimmed" ]; then
        continue
    fi

    boot_filename=$(basename "$original_boot_file_path_trimmed")
    new_boot_file_path="$NEW_BOOTSTRAP_DIR/$boot_filename"

    # echo "  -> 正在处理 '$original_boot_file_path_trimmed' -> '$new_boot_file_path'" # 可以取消注释以获取更详细日志
    process_tree_file "$original_boot_file_path_trimmed" "$new_boot_file_path"
    if [ $? -eq 0 ]; then
        echo "$new_boot_file_path" >> "$NEW_BOOTSTRAP_LIST_FILE"
        num_boot_processed=$((num_boot_processed + 1))
    else
        echo "错误: 处理 bootstrap 文件 '$original_boot_file_path_trimmed' 失败。" >&2
        num_boot_failed=$((num_boot_failed + 1))
    fi
done < "$ORIGINAL_BOOTSTRAP_LIST_FILE"

echo "INFO: 已处理 $num_boot_processed 个 bootstrap 文件。"
if [ "$num_boot_failed" -gt 0 ]; then
    echo "警告: $num_boot_failed 个 bootstrap 文件处理失败。" >&2
fi


# --- Completion ---
echo "=================================================="
echo "脚本执行完毕！"
echo "新的物种名映射树文件: $NEW_TREE_FILE"
echo "新的物种名映射 bootstrap 文件位于目录: $NEW_BOOTSTRAP_DIR"
echo "新的 bootstrap 文件列表: $NEW_BOOTSTRAP_LIST_FILE"
if [ "$num_boot_failed" -gt 0 ]; then
    echo "请检查与处理失败的 bootstrap 文件相关的错误信息。"
fi
echo "=================================================="

exit 0 