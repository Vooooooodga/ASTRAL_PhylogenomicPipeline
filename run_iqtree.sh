#!/bin/bash

# 中文注释：脚本功能：并行运行 IQ-TREE 构建基因树

# --- 用户可配置变量 ---
# 中文注释：输入包含 FASTA 文件的目录 (例如：/home/user/data/msa_files)
INPUT_DIR=""
# 中文注释：输出 IQ-TREE 结果的目录 (例如：/home/user/results/iqtree_gene_trees)
OUTPUT_DIR=""
# 中文注释：IQ-TREE 可执行文件的路径 (如果 iqtree2 不在系统 PATH 中，请指定完整路径，例如：/usr/local/bin/iqtree2)
IQTree_CMD="iqtree2"
# 中文注释：并行运行的 IQ-TREE 任务数量 (例如：8)
NUM_JOBS=4
# 中文注释：每个 IQ-TREE 任务使用的 CPU 核心数 (固定为 4)
THREADS_PER_JOB=4 # 非常重要: 确保每个 IQ-TREE 实例只占用4 CPU 核心

# --- 脚本主要逻辑 ---

# 中文注释：检查输入目录是否存在
if [ -z "$INPUT_DIR" ]; then
    echo "错误：请输入 INPUT_DIR (输入目录)。"
    exit 1
fi
if [ ! -d "$INPUT_DIR" ]; then
    echo "错误：输入目录 '$INPUT_DIR' 不存在。"
    exit 1
fi

# 中文注释：检查输出目录是否存在，如果不存在则创建
if [ -z "$OUTPUT_DIR" ]; then
    echo "错误：请输入 OUTPUT_DIR (输出目录)。"
    exit 1
fi
mkdir -p "$OUTPUT_DIR"
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "错误：无法创建输出目录 '$OUTPUT_DIR'。"
    exit 1
fi

echo "=================================================="
echo "          开始运行 IQ-TREE 构建基因树             "
echo "=================================================="
echo "输入目录: $INPUT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "IQ-TREE 命令: $IQTree_CMD"
echo "并行任务数: $NUM_JOBS"
echo "每个任务CPU核心数: $THREADS_PER_JOB"
echo "--------------------------------------------------"

# 中文注释：初始化并行任务计数器
job_count=0

# 中文注释：遍历输入目录中的所有 *_codon.clipkit.fasta 文件
for fasta_file in "$INPUT_DIR"/*_codon.clipkit.fasta; do
    if [ -f "$fasta_file" ]; then
        # 中文注释：获取文件名基本部分 (例如 OGxxxx_codon.clipkit)
        base_name=$(basename "$fasta_file" .fasta)

        echo "处理文件: $fasta_file"
        echo "输出文件前缀: $OUTPUT_DIR/$base_name"

        # 中文注释：IQ-TREE 命令
        # 默认使用 DNA 模型 (GTR+G+I)，因为它计算速度较快。
        # -s: 输入文件
        # -B 1000: Ultrafast Bootstrap, 1000 次重复
        # -m GTR+G+I: 模型选择 (DNA模型)
        # -T $THREADS_PER_JOB: 指定CPU核心数 (这里固定为4)
        # --prefix: 输出文件前缀
        # --quiet: 减少输出信息，避免日志过于庞大
        
        # 中文注释：实际执行的命令 (DNA 模型)
        $IQTree_CMD -s "$fasta_file" -B 1000 -m GTR+G+I -T $THREADS_PER_JOB --prefix "$OUTPUT_DIR/$base_name" --quiet &

        # 中文注释：备选方案：使用密码子模型 (例如 GTR+G+I+F)。
        # 密码子模型 (-st CODON -m MFP) 通常更为准确，但计算量巨大，耗时很长。
        # 如果需要使用密码子模型，请注释掉上面的 DNA 模型命令，并取消下面这行的注释。
        # 注意：MFP (ModelFinder Plus) 会自动选择最佳的密码子模型和核苷酸模型组合。
        # $IQTree_CMD -s "$fasta_file" -st CODON -m MFP -B 1000 -T $THREADS_PER_JOB --prefix "$OUTPUT_DIR/${base_name}_codon" --quiet &
        
        # 中文注释：增加任务计数器
        ((job_count++))

        # 中文注释：如果达到并行任务上限，则等待一个任务完成后再继续
        if [ $job_count -ge $NUM_JOBS ]; then
            echo "达到并行任务上限 ($NUM_JOBS)，等待一个任务完成..."
            wait -n  # 等待任意一个后台任务结束
            ((job_count--))
        fi
    else
        echo "警告: 未找到匹配 *_codon.clipkit.fasta 的文件于 '$INPUT_DIR' (或 '$fasta_file' 不是一个文件)"
        # 如果glob没有匹配到任何文件，它会保持原样，所以我们检查一下它是否真的是一个文件
        # 如果目录下没有匹配文件，这里会执行一次，所以最好在循环外检查文件列表是否为空
    fi
done

# 中文注释：等待所有剩余的后台任务完成
echo "--------------------------------------------------"
echo "所有 IQ-TREE 任务已提交，正在等待剩余任务完成..."
wait
echo "所有 IQ-TREE 任务已完成！"
echo "输出文件保存在: $OUTPUT_DIR"
echo "=================================================="

# 中文注释：脚本结束 