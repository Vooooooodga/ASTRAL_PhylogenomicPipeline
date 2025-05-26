#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import sys
import multiprocessing
import re # 新增导入

def parse_mapping_file(mapping_file_path):
    """
    解析 ASTRAL 映射文件。
    文件格式: 物种名:基因名1,基因名2,...
    返回一个字典: {基因名: 物种名}
    """
    gene_to_species_map = {}
    duplicate_map_warnings = []

    try:
        with open(mapping_file_path, 'r', encoding='utf-8') as f_map:
            for line_num, line in enumerate(f_map, 1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                parts = line.split(':', 1)
                if len(parts) != 2:
                    print(f"警告 (映射文件第 {line_num} 行): 格式不正确，缺少冒号分隔符，已跳过: '{line}'", file=sys.stderr)
                    continue

                species_name = parts[0].strip()
                genes_list_str = parts[1].strip()

                if not species_name:
                    print(f"警告 (映射文件第 {line_num} 行): 物种名为空，已跳过: '{line}'", file=sys.stderr)
                    continue
                
                if not genes_list_str: # 物种可能没有对应的基因，这本身是允许的
                    continue

                gene_leafs = [g.strip() for g in genes_list_str.split(',') if g.strip()]

                for gene_leaf in gene_leafs:
                    if gene_leaf in gene_to_species_map and gene_to_species_map[gene_leaf] != species_name:
                        warning_msg = (f"警告: 基因 '{gene_leaf}' 先前映射到 '{gene_to_species_map[gene_leaf]}', "
                                       f"现在在第 {line_num} 行被重新映射到 '{species_name}'。将使用后者 '{species_name}'。")
                        duplicate_map_warnings.append(warning_msg)
                    gene_to_species_map[gene_leaf] = species_name
        
        for warning in duplicate_map_warnings:
            print(warning, file=sys.stderr)
            
        if not gene_to_species_map:
            print(f"警告: 在映射文件 '{mapping_file_path}' 中未找到有效的基因到物种的映射。", file=sys.stderr)
        
        return gene_to_species_map
    except FileNotFoundError:
        print(f"错误: 映射文件 '{mapping_file_path}' 未找到。", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"错误: 读取映射文件 '{mapping_file_path}' 时发生错误: {e}", file=sys.stderr)
        sys.exit(1)


def process_tree_content(tree_content, gene_to_species_map, is_bootstrap_file=False):
    """
    替换树文件内容中的基因名为物种名。
    对每个物种，构建其所有对应基因名的正则表达式，然后执行一次 re.sub。
    is_bootstrap_file: 布尔值，指示当前处理的是否为bootstrap文件，用于调整正则模式。
    """
    modified_content = tree_content

    if not gene_to_species_map: # 如果映射为空，直接返回原始内容
        return modified_content

    # 1. 构建物种到基因列表的映射
    species_to_genes_map = {}
    for gene, species in gene_to_species_map.items():
        if species not in species_to_genes_map:
            species_to_genes_map[species] = []
        species_to_genes_map[species].append(gene)

    # 2. 遍历每个物种，为其关联的基因执行一次 re.sub
    for species_name, gene_names_list in species_to_genes_map.items():
        if not gene_names_list: # 如果该物种没有关联的基因，则跳过
            continue

        sorted_gene_names_for_species = sorted(gene_names_list, key=len, reverse=True)
        escaped_gene_names = [re.escape(g) for g in sorted_gene_names_for_species]
        
        # 根据是否为bootstrap文件选择不同的正则模式
        if is_bootstrap_file:
            # 对于 bootstrap 文件，假设叶节点名后不一定有冒号和分支长度
            # 匹配 (基因名) 后面可能跟着 (逗号 或 右括号 或 冒号 或 文件结束)
            # 使用  词边界确保匹配整个基因名
            pattern_string = r"\b(?:" + "|".join(escaped_gene_names) + r")\b(?=[,):]|$)"
            # print(f"DEBUG_BOOTSTRAP_PATTERN: {pattern_string[:100]}... for species {species_name}", file=sys.stderr) # 可选的调试打印
        else:
            # 对于主树文件，仍然使用原先更严格的模式（要求基因名后跟冒号）
            pattern_string = r"(?:" + "|".join(escaped_gene_names) + r")(?=:)"
        
        replacement_string = species_name
        modified_content = re.sub(pattern_string, replacement_string, modified_content)
        
    return modified_content


def process_single_tree_file(input_path, output_path, gene_to_species_map, is_bootstrap_file=False):
    """
    读取输入树文件，替换基因名，并将结果写入输出树文件。
    此函数会被worker调用，也用于主树文件。
    is_bootstrap_file: 传递给 process_tree_content 以选择正确的正则模式。
    """
    try:
        with open(input_path, 'r', encoding='utf-8') as f_in:
            content = f_in.read()
        
        # 将 is_bootstrap_file 参数传递下去
        modified_content = process_tree_content(content, gene_to_species_map, is_bootstrap_file)
        
        with open(output_path, 'w', encoding='utf-8') as f_out:
            f_out.write(modified_content)
        return True # 表示成功
    except FileNotFoundError:
        # 此处打印错误信息，以便worker可以捕获到是哪个文件找不到
        print(f"错误 (process_single_tree_file): 输入树文件 '{input_path}' 未找到。", file=sys.stderr)
        return False
    except Exception as e:
        print(f"错误 (process_single_tree_file): 处理树文件 '{input_path}' 到 '{output_path}' 失败: {e}", file=sys.stderr)
        return False

# --- Worker function for multiprocessing ---
# 必须是顶级函数才能被 pickle
def worker_process_bootstrap_file(original_boot_file_path, output_dir, gene_to_species_map_local):
    """
    Worker 函数，用于并行处理单个 bootstrap 文件。
    original_boot_file_path: 原始 bootstrap 文件的路径。
    output_dir: 保存修改后文件的目录。
    gene_to_species_map_local: 基因到物种的映射字典。
    返回新文件的路径 (如果成功)，否则返回 None。
    """
    # print(f"WORKER_DEBUG: 处理文件: {original_boot_file_path}", file=sys.stderr)
    # print(f"WORKER_DEBUG: 映射表大小: {len(gene_to_species_map_local)}", file=sys.stderr)
    try:
        boot_filename = os.path.basename(original_boot_file_path)
        new_boot_file_path = os.path.join(output_dir, boot_filename)

        # # DEBUG: 打印原始 bootstrap 文件内容片段
        # try:
        #     with open(original_boot_file_path, 'r', encoding='utf-8') as f_in_debug:
        #         original_content_debug = f_in_debug.read(500) # 只读前500字符
        #     print(f"WORKER_DEBUG: {original_boot_file_path} 原始内容片段:\n{original_content_debug}\n", file=sys.stderr)
        # except Exception as e_debug:
        #     print(f"WORKER_DEBUG: 读取原始文件 {original_boot_file_path} 片段失败: {e_debug}", file=sys.stderr)

        # 调用 process_single_tree_file 时，指明是 bootstrap 文件
        if process_single_tree_file(original_boot_file_path, new_boot_file_path, gene_to_species_map_local, is_bootstrap_file=True):
            
            # # DEBUG: 比较文件内容是否改变
            # try:
            #     with open(original_boot_file_path, 'r', encoding='utf-8') as f_orig_cmp:
            #         orig_data_cmp = f_orig_cmp.read()
            #     with open(new_boot_file_path, 'r', encoding='utf-8') as f_new_cmp:
            #         new_data_cmp = f_new_cmp.read()
            #     if orig_data_cmp == new_data_cmp:
            #         print(f"WORKER_DEBUG: 文件 {new_boot_file_path} 内容未发生改变!", file=sys.stderr)
            #     else:
            #         print(f"WORKER_DEBUG: 文件 {new_boot_file_path} 内容已修改。新内容片段:\n{new_data_cmp[:500]}\n", file=sys.stderr)
            # except Exception as e_cmp:
            #     print(f"WORKER_DEBUG: 比较文件 {new_boot_file_path} 时出错: {e_cmp}", file=sys.stderr)
            return new_boot_file_path 
        else:
            # print(f"WORKER_DEBUG: process_single_tree_file 对 {original_boot_file_path} 返回失败", file=sys.stderr)
            return None 
    except Exception as e:
        # 捕获 worker 内部的意外错误
        print(f"错误 (Worker): 处理文件 '{original_boot_file_path}' 时发生意外错误: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description="将 Newick 格式树文件中的基因叶节点名替换为对应的物种名。使用多进程加速 bootstrap 文件处理。",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""示例:
  python3 %(prog)s nc_best.trees nc_ml_boot.txt astral_mapping.txt nc_species_mapped"""
    )
    parser.add_argument("original_gene_tree_file", help="原始合并基因树文件的路径 (例如: nc_best.trees)")
    parser.add_argument("original_bootstrap_list_file", help="包含原始 bootstrap 树文件路径的列表文件 (例如: nc_ml_boot.txt)")
    parser.add_argument("astral_mapping_file", help="ASTRAL 映射文件的路径 (格式: 物种名:基因名1,基因名2,...)")
    parser.add_argument("output_basename", help="用于生成输出文件和目录的基本名称 (例如: nc_species_mapped)")
    parser.add_argument("--num_workers", type=int, default=os.cpu_count(), help="用于处理 bootstrap 文件的并行工作进程数量 (默认为系统CPU核心数)")


    args = parser.parse_args()

    # --- 定义输出名称 ---
    new_tree_file = f"{args.output_basename}.tre"
    new_bootstrap_dir = f"{args.output_basename}_bootstraps"
    new_bootstrap_list_file = f"{args.output_basename}_bootstraps.txt"

    # --- 输入文件校验 ---
    for f_path in [args.original_gene_tree_file, args.original_bootstrap_list_file, args.astral_mapping_file]:
        if not os.path.isfile(f_path):
            print(f"错误: 输入文件 '{f_path}' 未找到或不是一个有效文件。", file=sys.stderr)
            parser.print_help(sys.stderr)
            sys.exit(1)
        if not os.access(f_path, os.R_OK):
            print(f"错误: 输入文件 '{f_path}' 没有读取权限。", file=sys.stderr)
            parser.print_help(sys.stderr)
            sys.exit(1)

    # --- 创建输出目录 ---
    try:
        os.makedirs(new_bootstrap_dir, exist_ok=True)
        print(f"INFO: 输出目录 '{new_bootstrap_dir}' 已创建或已存在。")
    except OSError as e:
        print(f"错误: 无法创建输出目录 '{new_bootstrap_dir}': {e}", file=sys.stderr)
        sys.exit(1)

    # --- 解析映射文件 ---
    print(f"INFO: 正在读取映射文件 '{args.astral_mapping_file}'...")
    gene_to_species_map = parse_mapping_file(args.astral_mapping_file)
    
    if not gene_to_species_map:
        print(f"INFO: 映射表为空或未能成功加载。文件内容可能主要被复制而不做更改。", file=sys.stderr)
    else:
        print(f"INFO: 找到 {len(gene_to_species_map)} 个独特的基因到物种的映射关系。")

    # --- 处理主树文件 ---
    print(f"INFO: 正在处理主树文件 '{args.original_gene_tree_file}' -> '{new_tree_file}'...")
    # 主树文件调用 process_single_tree_file 时，is_bootstrap_file 默认为 False
    if not process_single_tree_file(args.original_gene_tree_file, new_tree_file, gene_to_species_map):
        print("错误: 处理主树文件失败。正在退出。", file=sys.stderr)
        sys.exit(1)

    # --- 处理 Bootstrap 文件 (并行) ---
    print(f"INFO: 准备处理来自 '{args.original_bootstrap_list_file}' 的 bootstrap 文件，输出到目录 '{new_bootstrap_dir}'...")
    
    tasks_for_workers = []
    bootstrap_paths_not_found_or_unreadable = 0

    try:
        with open(args.original_bootstrap_list_file, 'r', encoding='utf-8') as f_orig_list:
            for line_num, original_boot_file_path_raw in enumerate(f_orig_list, 1):
                #加强清理，移除可能的
                original_boot_file_path = original_boot_file_path_raw.rstrip('\r\n').strip()
                if not original_boot_file_path: # 跳过空行
                    continue

                if not os.path.isfile(original_boot_file_path):
                    print(f"警告 (bootstrap列表文件 第 {line_num} 行): 文件 '{original_boot_file_path}' 未找到或不是有效文件，已跳过。", file=sys.stderr)
                    bootstrap_paths_not_found_or_unreadable += 1
                    continue
                tasks_for_workers.append((original_boot_file_path, new_bootstrap_dir, gene_to_species_map))
    except FileNotFoundError:
        print(f"错误: 原始 bootstrap 列表文件 '{args.original_bootstrap_list_file}' 未找到。", file=sys.stderr)
        sys.exit(1) 
    except Exception as e:
        print(f"错误: 读取原始 bootstrap 列表文件 '{args.original_bootstrap_list_file}' 时发生未知错误: {e}", file=sys.stderr)
        sys.exit(1)

    processed_new_boot_paths = []
    if tasks_for_workers:
        num_actual_workers = min(args.num_workers, len(tasks_for_workers))
        if num_actual_workers <= 0 : num_actual_workers = 1 

        print(f"INFO: 使用 {num_actual_workers} 个工作进程并行处理 {len(tasks_for_workers)} 个 bootstrap 文件...")
        
        with multiprocessing.Pool(processes=num_actual_workers) as pool:
            results = pool.starmap(worker_process_bootstrap_file, tasks_for_workers)
        
        processed_new_boot_paths = [path for path in results if path is not None] 
        num_boot_processed_successfully = len(processed_new_boot_paths)
        num_boot_processing_failed_in_workers = len(tasks_for_workers) - num_boot_processed_successfully
    else:
        print("INFO: 没有 bootstrap 文件需要处理。")
        num_boot_processed_successfully = 0
        num_boot_processing_failed_in_workers = 0
        
    try:
        with open(new_bootstrap_list_file, 'w', encoding='utf-8') as f_new_list:
            if processed_new_boot_paths:
                for new_path in processed_new_boot_paths:
                    f_new_list.write(f"{new_path}\n") # 确保 Unix 换行符
        print(f"INFO: 新的 bootstrap 列表文件 '{new_bootstrap_list_file}' 已生成。")
    except IOError as e:
        print(f"错误: 无法写入新的 bootstrap 列表文件 '{new_bootstrap_list_file}': {e}", file=sys.stderr)
        
    total_boot_failed = bootstrap_paths_not_found_or_unreadable + num_boot_processing_failed_in_workers

    print(f"INFO: 已成功处理 {num_boot_processed_successfully} 个 bootstrap 文件。")
    if total_boot_failed > 0:
        print(f"警告: 总共有 {total_boot_failed} 个 bootstrap 文件未能处理 (包括未找到或处理中失败)。", file=sys.stderr)

    # --- 完成 ---
    print("==================================================")
    print("脚本执行完毕！")
    print(f"  新的物种名映射树文件: {new_tree_file}")
    print(f"  新的物种名映射 bootstrap 文件位于目录: {new_bootstrap_dir}")
    print(f"  新的 bootstrap 文件列表: {new_bootstrap_list_file}")
    if total_boot_failed > 0:
        print("  请检查以上与处理失败的 bootstrap 文件相关的错误或警告信息。")
    print("==================================================")

if __name__ == "__main__":
    # 在 Windows 上使用 multiprocessing 时，需要此保护块。
    # 它确保 main() 只在脚本直接运行时执行，而不是在每个子进程中重新执行。
    # 对于 Linux/macOS，它也是一个好习惯。
    multiprocessing.freeze_support() # 对于打包成可执行文件时有用 (如用PyInstaller)
    main() 