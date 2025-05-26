#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import sys

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


def process_tree_content(tree_content, gene_to_species_map):
    """
    替换树文件内容中的基因名为物种名。
    基因名按长度降序排序后进行替换，以正确处理子字符串情况。
    替换 "基因名:" 为 "物种名:"。
    """
    modified_content = tree_content
    
    # 按基因名长度降序排序，确保长名优先替换 (例如 "ABC_1" 在 "ABC" 之前)
    # 这对于 simple string.replace(f"{gene}:", f"{species}:") 策略很重要
    sorted_gene_names = sorted(gene_to_species_map.keys(), key=len, reverse=True)

    for gene_name in sorted_gene_names:
        species_name = gene_to_species_map[gene_name]
        
        # 构建查找和替换的模式： "基因名:" -> "物种名:"
        # 这是 Newick 格式中叶节点名的常见形式 (LeafName:BranchLength)
        find_pattern = f"{gene_name}:"
        replace_with = f"{species_name}:"
        modified_content = modified_content.replace(find_pattern, replace_with)
        
    return modified_content

def process_single_tree_file(input_path, output_path, gene_to_species_map):
    """
    读取输入树文件，替换基因名，并将结果写入输出树文件。
    """
    try:
        with open(input_path, 'r', encoding='utf-8') as f_in:
            content = f_in.read()
        
        modified_content = process_tree_content(content, gene_to_species_map)
        
        with open(output_path, 'w', encoding='utf-8') as f_out:
            f_out.write(modified_content)
        return True
    except FileNotFoundError:
        print(f"错误: 输入树文件 '{input_path}' 未找到。", file=sys.stderr)
        return False
    except Exception as e:
        print(f"错误: 处理树文件 '{input_path}' 到 '{output_path}' 失败: {e}", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(
        description="将 Newick 格式树文件中的基因叶节点名替换为对应的物种名。",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""示例:
  python3 %(prog)s nc_best.trees nc_ml_boot.txt astral_mapping.txt nc_species_mapped"""
    )
    parser.add_argument("original_gene_tree_file", help="原始合并基因树文件的路径 (例如: nc_best.trees)")
    parser.add_argument("original_bootstrap_list_file", help="包含原始 bootstrap 树文件路径的列表文件 (例如: nc_ml_boot.txt)")
    parser.add_argument("astral_mapping_file", help="ASTRAL 映射文件的路径 (格式: 物种名:基因名1,基因名2,...)")
    parser.add_argument("output_basename", help="用于生成输出文件和目录的基本名称 (例如: nc_species_mapped)")

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
    if not process_single_tree_file(args.original_gene_tree_file, new_tree_file, gene_to_species_map):
        print("错误: 处理主树文件失败。正在退出。", file=sys.stderr)
        sys.exit(1)

    # --- 处理 Bootstrap 文件 ---
    print(f"INFO: 正在处理来自 '{args.original_bootstrap_list_file}' 的 bootstrap 文件，输出到目录 '{new_bootstrap_dir}'...")
    
    num_boot_processed = 0
    num_boot_failed = 0
    
    try:
        with open(new_bootstrap_list_file, 'w', encoding='utf-8') as f_new_list:
            try:
                with open(args.original_bootstrap_list_file, 'r', encoding='utf-8') as f_orig_list:
                    for line_num, original_boot_file_path_raw in enumerate(f_orig_list, 1):
                        original_boot_file_path = original_boot_file_path_raw.strip()
                        if not original_boot_file_path: # 跳过空行
                            continue

                        if not os.path.isfile(original_boot_file_path):
                            print(f"警告 (bootstrap列表文件 第 {line_num} 行): 文件 '{original_boot_file_path}' 未找到或不是有效文件，已跳过。", file=sys.stderr)
                            num_boot_failed += 1
                            continue
                        
                        boot_filename = os.path.basename(original_boot_file_path)
                        new_boot_file_path = os.path.join(new_bootstrap_dir, boot_filename)

                        if process_single_tree_file(original_boot_file_path, new_boot_file_path, gene_to_species_map):
                            f_new_list.write(f"{new_boot_file_path}\n")
                            num_boot_processed += 1
                        else:
                            # 错误信息已由 process_single_tree_file 打印
                            num_boot_failed += 1
            except FileNotFoundError:
                print(f"错误: 原始 bootstrap 列表文件 '{args.original_bootstrap_list_file}' 未找到。", file=sys.stderr)
                sys.exit(1) 
            except Exception as e:
                print(f"错误: 读取原始 bootstrap 列表文件 '{args.original_bootstrap_list_file}' 时发生未知错误: {e}", file=sys.stderr)
                sys.exit(1)
    except IOError as e:
        print(f"错误: 无法写入新的 bootstrap 列表文件 '{new_bootstrap_list_file}': {e}", file=sys.stderr)
        sys.exit(1)

    print(f"INFO: 已成功处理 {num_boot_processed} 个 bootstrap 文件。")
    if num_boot_failed > 0:
        print(f"警告: {num_boot_failed} 个 bootstrap 文件处理失败或被跳过。", file=sys.stderr)

    # --- 完成 ---
    print("==================================================")
    print("脚本执行完毕！")
    print(f"  新的物种名映射树文件: {new_tree_file}")
    print(f"  新的物种名映射 bootstrap 文件位于目录: {new_bootstrap_dir}")
    print(f"  新的 bootstrap 文件列表: {new_bootstrap_list_file}")
    if num_boot_failed > 0:
        print("  请检查以上与处理失败的 bootstrap 文件相关的错误或警告信息。")
    print("==================================================")

if __name__ == "__main__":
    main() 