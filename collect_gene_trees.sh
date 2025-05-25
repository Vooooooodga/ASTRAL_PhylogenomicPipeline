#!/bin/bash

# 中文注释：脚本功能：收集所有 IQ-TREE 生成的基因树文件 (.treefile) 并合并到一个文件，用于 ASTRAL 分析

# --- 用户可配置变量 ---
# 中文注释：包含 IQ-TREE 输出基因树文件 (.treefile) 的目录 (例如：/home/user/results/iqtree_gene_trees)
GENE_TREES_DIR=""
# 中文注释：合并后的基因树文件的输出路径和文件名 (例如：/home/user/results/all_gene_trees.nwk)
OUTPUT_MERGED_TREES_FILE=""

# --- 脚本主要逻辑 ---

# 中文注释：检查基因树目录是否存在
if [ -z "$GENE_TREES_DIR" ]; then
    echo "错误：请输入 GENE_TREES_DIR (基因树文件所在目录)。"
    exit 1
fi
if [ ! -d "$GENE_TREES_DIR" ]; then
    echo "错误：基因树目录 '$GENE_TREES_DIR' 不存在。"
    exit 1
fi

# 中文注释：检查输出文件名是否提供
if [ -z "$OUTPUT_MERGED_TREES_FILE" ]; then
    echo "错误：请输入 OUTPUT_MERGED_TREES_FILE (合并后的基因树文件名)。"
    exit 1
fi

echo "=================================================="
echo "        开始收集并合并基因树 (.treefile)         "
echo "=================================================="
echo "基因树输入目录: $GENE_TREES_DIR"
echo "合并后输出文件: $OUTPUT_MERGED_TREES_FILE"
echo "--------------------------------------------------"

# 中文注释：删除可能已存在的旧合并文件，以避免重复追加
if [ -f "$OUTPUT_MERGED_TREES_FILE" ]; then
    echo "警告：发现已存在的合并文件 '$OUTPUT_MERGED_TREES_FILE'，将进行覆盖。"
    rm -f "$OUTPUT_MERGED_TREES_FILE"
fi

# 中文注释：查找所有 .treefile 文件并合并
# 使用 find 命令查找所有以 .treefile 结尾的文件
# -type f 表示只查找普通文件
# -print0 和 xargs -0 配合使用，可以更好地处理包含特殊字符的文件名
# 使用 cat 将每个文件的内容追加到输出文件，每个树在新的一行

num_tree_files_found=$(find "$GENE_TREES_DIR" -name '*.treefile' -type f | wc -l)

if [ "$num_tree_files_found" -eq 0 ]; then
    echo "错误：在目录 '$GENE_TREES_DIR' 中未找到任何 .treefile 文件。"
    echo "请确保 run_iqtree.sh 脚本已成功运行并且生成了 .treefile 文件。"
    echo "=================================================="
    exit 1
fi

echo "找到 $num_tree_files_found 个 .treefile 文件，正在合并..."

find "$GENE_TREES_DIR" -name '*.treefile' -type f -print0 | while IFS= read -r -d $'\0' tree_file; do
    echo "添加文件: $tree_file 到 $OUTPUT_MERGED_TREES_FILE"
    cat "$tree_file" >> "$OUTPUT_MERGED_TREES_FILE"
    echo "" >> "$OUTPUT_MERGED_TREES_FILE" # 确保每个树在新的一行，IQ-TREE的.treefile本身通常只有一行
done

echo "--------------------------------------------------"
echo "所有基因树已成功合并到: $OUTPUT_MERGED_TREES_FILE"
echo "=================================================="

# 中文注释：脚本结束 