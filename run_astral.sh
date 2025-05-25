#!/bin/bash

# 中文注释：脚本功能：使用 ASTRAL 基于合并后的基因树文件构建物种树

# --- 用户可配置变量 ---
# 中文注释：包含所有基因树的合并文件 (由 collect_gene_trees.sh 生成)
INPUT_MERGED_TREES_FILE=""
# 中文注释：ASTRAL 输出的物种树文件名 (例如：/home/user/results/species_tree.tre)
OUTPUT_SPECIES_TREE_FILE=""
# 中文注释：ASTRAL .jar 文件的路径 (例如：/path/to/astral.5.7.8.jar)
# 如果 astral 在系统 PATH 中并且可以直接作为命令运行，可以将此设置为空或 "astral"
ASTRAL_JAR_PATH=""
# 中文注释：ASTRAL运行时可分配的最大内存 (例如："4G" 表示 4 Gigabytes)
ASTRAL_MEMORY="4G"

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

# 中文注释：检查 ASTRAL JAR 路径是否提供 (如果直接用 astral 命令，则不需要)
if [ -z "$ASTRAL_JAR_PATH" ]; then
    echo "信息：未指定 ASTRAL_JAR_PATH，将尝试直接使用 'astral' 命令。请确保 astral 已安装并配置在系统 PATH 中。"
    ASTRAL_CMD="astral"
else
    if [ ! -f "$ASTRAL_JAR_PATH" ]; then
        echo "错误：ASTRAL jar 文件 '$ASTRAL_JAR_PATH' 不存在。"
        exit 1
    fi
    ASTRAL_CMD="java -Xmx${ASTRAL_MEMORY} -jar $ASTRAL_JAR_PATH"
echo "使用 ASTRAL JAR: $ASTRAL_JAR_PATH"
fi

echo "=================================================="
echo "            开始运行 ASTRAL 构建物种树             "
echo "=================================================="
echo "输入合并基因树文件: $INPUT_MERGED_TREES_FILE"
echo "输出物种树文件: $OUTPUT_SPECIES_TREE_FILE"
echo "ASTRAL 命令: $ASTRAL_CMD"
echo "ASTRAL 最大内存: $ASTRAL_MEMORY"
echo "--------------------------------------------------"

# 中文注释：运行 ASTRAL
# -i: 输入基因树文件
# -o: 输出物种树文件
# ASTRAL 会自动处理带自举支持的基因树

# 中文注释：ASTRAL 的输出通常直接到标准输出，如果指定 -o，则输出到文件。
# 同时，ASTRAL 可能会在标准错误输出一些日志信息。
# 我们将标准输出重定向到指定的输出文件，标准错误也重定向，以便调试。

echo "正在运行 ASTRAL... 这可能需要一些时间，具体取决于基因树的数量和大小。"

$ASTRAL_CMD -i "$INPUT_MERGED_TREES_FILE" -o "$OUTPUT_SPECIES_TREE_FILE" 2> "${OUTPUT_SPECIES_TREE_FILE%.*}.log"

# 中文注释：检查 ASTRAL 是否成功运行
# ASTRAL 成功时返回码为 0
if [ $? -eq 0 ]; then
    echo "--------------------------------------------------"
    echo "ASTRAL 成功完成！"
    echo "物种树保存在: $OUTPUT_SPECIES_TREE_FILE"
    echo "ASTRAL 日志保存在: ${OUTPUT_SPECIES_TREE_FILE%.*}.log"
else
    echo "--------------------------------------------------"
    echo "错误：ASTRAL 运行失败。"
    echo "请检查日志文件: ${OUTPUT_SPECIES_TREE_FILE%.*}.log 获取更多信息。"
    echo "=================================================="
    exit 1
fi

echo "=================================================="

# 中文注释：脚本结束 