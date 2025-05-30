#!/bin/bash

#SBATCH --job-name=astral_species_tree
#SBATCH --output=astral_species_tree_%j.out
#SBATCH --error=astral_species_tree_%j.err
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G

# 中文注释：脚本功能：使用 ASTRAL 基于合并后的基因树文件构建物种树

# --- 用户可配置变量 ---
# ******************************************************************
# ** 请务必在这里设置正确的文件路径！**
# 中文注释：包含所有基因树的合并文件 (例如: ml_best.trees)
INPUT_MERGED_TREES_FILE="aa_species_mapped.tre"
# 中文注释：包含所有 Bootstrap 树文件名的列表文件 (例如: ml_boot.txt)
# 如果您不想使用 Bootstrap 支持度，请将此行注释掉或留空。
INPUT_BOOTSTRAP_LIST_FILE="aa_species_mapped_bootstraps.txt"
# 中文注释：ASTRAL 物种/基因映射文件 (例如: astral_mapping.txt)
# 使用 -a 选项时需要。如果不需要，请留空或注释掉。
# ASTRAL_MAPPING_FILE="astral_mapping.txt" # COMMENTED OUT: Python脚本已完成映射，不再需要此文件和 -a 选项
# 中文注释：ASTRAL 输出的物种树文件名 (例如：astral_species_tree.tre)
OUTPUT_SPECIES_TREE_FILE="astral_species_tree_with_aa.tree"
# ******************************************************************
# 中文注释：ASTRAL 的可执行命令。可以是简单的命令名 (如 'astral')，
# 也可以是完整的路径 (如 '/usr/local/bin/astral')，
# 或者是包含容器执行的命令 (如 'singularity exec ... astral')。
# 用户负责确保此命令能正确调用 ASTRAL，并处理 Java 内存 (如果需要，可通过 ASTRAL_JAVA_MEMORY 和 _JAVA_OPTIONS)。
ASTRAL_EXEC_COMMAND="singularity exec /usr/local/biotools/a/astral-tree:5.7.8--hdfd78af_0 astral"
# 中文注释：期望传递给 Java 运行 ASTRAL 的最大内存 (例如："4G" 表示 4 Gigabytes)。
# 注意：此设置将通过 _JAVA_OPTIONS 环境变量尝试传递给 Java。它的实际效果
# 取决于 ASTRAL_EXEC_COMMAND 中的命令如何最终调用 Java 进程。
ASTRAL_JAVA_MEMORY="60G" # 从 64G 调整为 60G，为 Java 非堆内存和系统开销留出余量

# --- 脚本主要逻辑 ---

# 中文注释：检查合并的基因树文件是否存在
if [ -z "$INPUT_MERGED_TREES_FILE" ]; then
    echo "错误：请输入 INPUT_MERGED_TREES_FILE (包含所有基因树的合并文件)。"
    exit 1
fi
if [ ! -f "$INPUT_MERGED_TREES_FILE" ]; then
    echo "错误：合并的基因树文件 '$INPUT_MERGED_TREES_FILE' 不存在。"
    exit 1
fi

# 中文注释：检查输出文件名是否提供
if [ -z "$OUTPUT_SPECIES_TREE_FILE" ]; then
    echo "错误：请输入 OUTPUT_SPECIES_TREE_FILE (ASTRAL 输出的物种树文件名)。"
    exit 1
fi

# 中文注释：检查可选的 Bootstrap 列表文件是否存在 (如果已提供)
if [ -n "$INPUT_BOOTSTRAP_LIST_FILE" ] && [ ! -f "$INPUT_BOOTSTRAP_LIST_FILE" ]; then
    echo "错误：Bootstrap 列表文件 '$INPUT_BOOTSTRAP_LIST_FILE' 已指定但不存在。"
    exit 1
fi

# 中文注释：检查可选的映射文件是否存在 (如果已提供)
# if [ -n "$ASTRAL_MAPPING_FILE" ] && [ ! -f "$ASTRAL_MAPPING_FILE" ]; then # COMMENTED OUT: 不再检查映射文件
#     echo "错误：ASTRAL 映射文件 '$ASTRAL_MAPPING_FILE' 已指定但不存在。" # COMMENTED OUT
#     echo "提示：该文件通常由 generating_astral_mapping.sh 脚本生成，名为 astral_mapping.txt。" # COMMENTED OUT
#     exit 1 # COMMENTED OUT
# fi # COMMENTED OUT

# 中文注释：检查 ASTRAL 执行命令是否提供
if [ -z "$ASTRAL_EXEC_COMMAND" ]; then
    echo "错误：ASTRAL_EXEC_COMMAND (ASTRAL 执行命令) 未设置。"
    exit 1
fi

echo "=================================================="
echo "            开始运行 ASTRAL 构建物种树             "
echo "=================================================="
echo "输入合并基因树文件: $INPUT_MERGED_TREES_FILE"
if [ -n "$INPUT_BOOTSTRAP_LIST_FILE" ]; then
    echo "输入 Bootstrap 列表文件: $INPUT_BOOTSTRAP_LIST_FILE"
fi
# if [ -n "$ASTRAL_MAPPING_FILE" ]; then # COMMENTED OUT
#     echo "输入 ASTRAL 映射文件: $ASTRAL_MAPPING_FILE" # COMMENTED OUT
# fi # COMMENTED OUT
echo "输出物种树文件: $OUTPUT_SPECIES_TREE_FILE"
echo "ASTRAL 执行命令: $ASTRAL_EXEC_COMMAND"
echo "ASTRAL Java 内存 (尝试通过 _JAVA_OPTIONS): $ASTRAL_JAVA_MEMORY"
echo "--------------------------------------------------"

# --- 新增：检查映射文件中各物种对应的叶节点数量 ---
# if [ -n "$ASTRAL_MAPPING_FILE" ] && [ -f "$ASTRAL_MAPPING_FILE" ]; then # COMMENTED OUT: 此检查依赖于映射文件，也应移除或调整
#     echo "INFO: 开始检查映射文件 '$ASTRAL_MAPPING_FILE' 中各物种对应的叶节点数量..."
#     first_count=""
#     all_counts_equal=true
#     declare -A species_leaf_counts # 用于存储每个物种的叶节点计数
# 
#     # 读取映射文件并处理每一行
#     line_number=0
#     processed_species_count=0
#     while IFS= read -r line || [ -n "$line" ]; do # 处理可能没有换行符的最后一行
#         line_number=$((line_number + 1))
#         # 跳过空行或注释行 (如果您的映射文件可能有注释)
#         [[ "$line" =~ ^[[:space:]]*# ]] && continue
#         [[ "$line" =~ ^[[:space:]]*$ ]] && continue
# 
#         # 按第一个冒号分割
#         base_species=$(echo "$line" | cut -d':' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#         leaves_list=$(echo "$line" | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
# 
#         if [ -z "$base_species" ] || ! echo "$line" | grep -q ':'; then
#             echo "警告 (映射文件第 $line_number 行): 格式不正确或缺少冒号分隔符，已跳过: '$line'"
#             continue
#         fi
# 
#         current_count=0
#         if [ -n "$leaves_list" ]; then
#             # 计算逗号分隔的叶节点数量
#             current_count=$(echo "$leaves_list" | tr ',' '\n' | wc -l)
#         fi
#         
#         species_leaf_counts["$base_species"]=$current_count
#         echo "  物种 '$base_species' 对应 $current_count 个基因树叶节点。"
#         processed_species_count=$((processed_species_count + 1))
# 
#         if [ -z "$first_count" ]; then
#             first_count=$current_count
#         elif [ "$first_count" -ne "$current_count" ]; then
#             all_counts_equal=false
#         fi
#     done < "$ASTRAL_MAPPING_FILE"
# 
#     if [ "$processed_species_count" -eq 0 ]; then
#         echo "警告：映射文件 '$ASTRAL_MAPPING_FILE' 为空或所有行均无法处理。"
#     elif $all_counts_equal; then
#         echo "INFO：检查完成。映射文件中所有 $processed_species_count 个已处理物种都对应相同数量 ($first_count) 的叶节点。"
#     else
#         echo "警告：检查完成。映射文件中的 $processed_species_count 个已处理物种对应的叶节点数量不完全相同。请检查以上列表。"
#     fi
#     echo "--------------------------------------------------"
# else
#     echo "INFO：未提供或未找到 ASTRAL 映射文件 '$ASTRAL_MAPPING_FILE'，跳过叶节点计数检查。" # MODIFIED: 调整此处的提示信息
#     echo "INFO: 由于基因名已预先转换为物种名，跳过基于原始映射文件的叶节点计数检查。"
#     echo "--------------------------------------------------"
# fi # COMMENTED OUT: 结束此检查块
# --- 检查结束 ---

# 中文注释：运行 ASTRAL
# -i: 输入基因树文件
# -o: 输出物种树文件
# ASTRAL 会自动处理带自举支持的基因树

echo "正在运行 ASTRAL... 这可能需要一些时间，具体取决于基因树的数量和大小。"

# 中文注释：设置 _JAVA_OPTIONS 环境变量，尝试将内存设置传递给 ASTRAL 内部的 Java 调用。
# 然后执行 ASTRAL 命令，并将标准错误输出重定向到日志文件。
export _JAVA_OPTIONS="-Xmx${ASTRAL_JAVA_MEMORY}"
echo "设置 _JAVA_OPTIONS=${_JAVA_OPTIONS} (将通过 singularity --env 传递)" # 显示设置，便于调试

# 构建 ASTRAL 命令数组
# 旧的初始化方式: astral_cmd_array=($ASTRAL_EXEC_COMMAND)

# 新的初始化方式，以通过 --env 传递 _JAVA_OPTIONS
# ASTRAL_EXEC_COMMAND 格式假定为 "singularity exec <image_path> <command_in_image>"
# 例如: "singularity exec /path/to/image.sif astral_command"

# 提取 "singularity exec " 之后的部分 (即 "<image_path> <command_in_image>")
remaining_args="${ASTRAL_EXEC_COMMAND#singularity exec }"
# 将剩余参数安全地解析到数组中，以正确处理任何潜在的空格（尽管在此特定示例中镜像路径和命令不包含空格）
read -ra image_and_command_elements <<< "$remaining_args"

astral_cmd_array=("singularity" "exec")
astral_cmd_array+=("--env" "_JAVA_OPTIONS=${_JAVA_OPTIONS}") # 明确传递 _JAVA_OPTIONS 的当前值
astral_cmd_array+=("${image_and_command_elements[@]}")     # 添加解析出的镜像路径和镜像内命令

astral_cmd_array+=(-i "$INPUT_MERGED_TREES_FILE")
astral_cmd_array+=(-o "$OUTPUT_SPECIES_TREE_FILE")

# 添加外群参数
astral_cmd_array+=(--outgroup "Drosophila_melanogaster")

# 添加 -r 参数
astral_cmd_array+=(-r 1000)

# if [ -n "$ASTRAL_MAPPING_FILE" ]; then # COMMENTED OUT: 不再添加 -a
#     astral_cmd_array+=(-a "$ASTRAL_MAPPING_FILE") # COMMENTED OUT
#     astral_cmd_array+=(-R) # COMMENTED OUT: -R 通常与 -a 配合，此处也注释掉
# fi # COMMENTED OUT

# if [ -n "$INPUT_BOOTSTRAP_LIST_FILE" ]; then # MODIFIED: 如果提供了bootstrap文件，则添加 -b (这个判断本身是好的)
#     astral_cmd_array+=(-b "$INPUT_BOOTSTRAP_LIST_FILE")
# fi
# ^^^ 上面的 if 判断 INPUT_BOOTSTRAP_LIST_FILE 是为了处理用户可能完全不提供bootstrap的情况。
# 如果您的工作流程总是会提供 bootstrap 文件（即使是空的列表文件），则可以直接添加 -b。
# 但为了安全和通用性，保留对 INPUT_BOOTSTRAP_LIST_FILE 的检查是好的。
# 确保 -b 选项在提供了 INPUT_BOOTSTRAP_LIST_FILE 时被添加：
if [ -n "$INPUT_BOOTSTRAP_LIST_FILE" ] && [ -f "$INPUT_BOOTSTRAP_LIST_FILE" ]; then # 确保文件实际存在
    astral_cmd_array+=(-b "$INPUT_BOOTSTRAP_LIST_FILE")
fi

echo "执行命令: ${astral_cmd_array[@]}"
"${astral_cmd_array[@]}" 2> "${OUTPUT_SPECIES_TREE_FILE%.*}.log"

exit_code=$?

# 中文注释：清理环境变量
unset _JAVA_OPTIONS
echo "已取消设置 _JAVA_OPTIONS"

# 中文注释：检查 ASTRAL 是否成功运行
# ASTRAL 成功时返回码为 0
if [ $exit_code -eq 0 ]; then
    echo "--------------------------------------------------"
    echo "ASTRAL 成功完成！"
    echo "物种树保存在: $OUTPUT_SPECIES_TREE_FILE"
    echo "ASTRAL 日志保存在: ${OUTPUT_SPECIES_TREE_FILE%.*}.log"
else
    echo "--------------------------------------------------"
    echo "错误：ASTRAL 运行失败 (退出码: $exit_code)。"
    echo "请检查日志文件: ${OUTPUT_SPECIES_TREE_FILE%.*}.log 获取更多信息。"
    echo "同时检查 _JAVA_OPTIONS 是否被 ASTRAL 命令正确解析。"
    echo "=================================================="
    exit 1
fi

echo "=================================================="

# 中文注释：脚本结束 