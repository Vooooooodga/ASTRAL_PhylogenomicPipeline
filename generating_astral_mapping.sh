#!/bin/bash

# --- 配置 ---
# 包含 .treefile 文件的目录
IQ_TREE_DIR="iqtree_results"
# 输出的映射文件名
OUTPUT_MAP_FILE="mapping.txt"
# 临时文件，用于存放所有叶节点名
LEAF_NAMES_TMP="all_leaf_names.tmp"

# --- 基础物种名列表 (根据您提供的列表生成) ---
# 注意：已移除 .fna 后缀
BASE_NAMES=(
"Acromyrmex_echinatior"
"Apis_cerana"
"Apis_dorsata"
"Apis_florea"
"Apis_laboriosa"
"Apis_mellifera"
"Atta_cephalotes"
"Atta_colombica"
"Bombus_affinis"
"Bombus_bifarius"
"Bombus_fervidus"
"Bombus_flavifrons"
"Bombus_huntii"
"Bombus_impatiens"
"Bombus_pascuorum"
"Bombus_pyrosoma"
"Bombus_terrestris"
"Bombus_vancouverensis_nearcticus" # 包含亚种名
"Bombus_vosnesenskii"
"Camponotus_floridanus"
"Cardiocondyla_obscurior"
"Cataglyphis_hispanica"
"Ceratina_calcarata"
"Colletes_gigas"
"Cyphomyrmex_costatus"
"Dinoponera_quadriceps"
"Drosophila_melanogaster"
"Dufourea_novaeangliae"
"Eufriesea_mexicana"
"Formica_exsecta"
"Frieseomelitta_varia"
"Habropoda_laboriosa"
"Harpegnathos_saltator"
"Hylaeus_anthracinus"
"Hylaeus_volcanicus"
"Linepithema_humile"
"Megachile_rotundata"
"Megalopta_genalis"
"Monomorium_pharaonis"
"Nomia_melanderi"
"Nylanderia_fulva"
"Odontomachus_brunneus"
"Ooceraea_biroi"
"Osmia_bicornis_bicornis" # 包含亚种名
"Osmia_lignaria"
"Pogonomyrmex_barbatus"
"Polistes_canadensis"
"Polistes_dominula"
"Polistes_fuscatus"
"Polyergus_mexicanus"
"Prorops_nasuta"
"Pseudomyrmex_gracilis"
"Solenopsis_invicta"
"Temnothorax_curvispinosus"
"Temnothorax_longispinosus"
"Temnothorax_nylanderi"
"Trachymyrmex_cornetzi"
"Trachymyrmex_septentrionalis"
"Trachymyrmex_zeteki"
"Vespa_crabro"
"Vespa_mandarinia"
"Vespa_velutina"
"Vespula_pensylvanica"
"Vespula_vulgaris"
"Vollenhovia_emeryi"
"Wasmannia_auropunctata"
)

# --- 检查 ---
if [ ! -d "$IQ_TREE_DIR" ]; then
    echo "错误: IQ-TREE 结果目录 '$IQ_TREE_DIR' 不存在！"
    exit 1
fi

if [ ! -n "$(find "$IQ_TREE_DIR" -maxdepth 1 -name '*.treefile' -print -quit)" ]; then
    echo "错误: 在 '$IQ_TREE_DIR' 中找不到任何 '.treefile' 文件。"
    exit 1
fi

# --- 脚本主要逻辑 ---

echo "🗺️ 开始生成 ASTRAL 映射文件..."

# 1. 提取所有唯一的叶节点名
echo "  -> 正在从 $IQ_TREE_DIR/*.treefile 提取所有叶节点名..."
grep -hoE '[^(),:;]+:[^(),:;]+' "$IQ_TREE_DIR"/*.treefile | \
    cut -d':' -f1 | \
    sort | \
    uniq > "$LEAF_NAMES_TMP"
echo "  -> 找到 $(wc -l < "$LEAF_NAMES_TMP") 个独特的叶节点名。"

# 2. 使用 Python 进行最长前缀匹配并生成映射文件
echo "  -> 正在匹配基础物种名并生成 $OUTPUT_MAP_FILE..."

# 将 Bash 数组转换为 Python 可读的列表字符串
PYTHON_BASE_NAMES="['$(printf "', '" "${BASE_NAMES[@]}")']"

python3 - << EOF
import sys

# 从 Bash 获取基础物种名列表
base_names = $PYTHON_BASE_NAMES
# 按长度降序排序，确保优先匹配长名称 (如亚种名)
base_names.sort(key=len, reverse=True)

# 初始化映射字典
mapping = {bn: [] for bn in base_names}
unmatched = []
matched_leaves = set()

# 读取所有叶节点名
try:
    with open('$LEAF_NAMES_TMP', 'r') as f:
        leaf_names = [line.strip() for line in f if line.strip()]
except FileNotFoundError:
    print("错误: 临时文件 '$LEAF_NAMES_TMP' 未找到。", file=sys.stderr)
    sys.exit(1)

# 进行匹配
for leaf in leaf_names:
    found = False
    for base in base_names:
        # 检查是否以基础名开头，并且要么完全相同，要么后面跟 '_' 或 '-'
        if leaf.startswith(base) and (len(leaf) == len(base) or leaf[len(base)] in ['_', '-']):
            mapping[base].append(leaf)
            matched_leaves.add(leaf)
            found = True
            break
    if not found:
        unmatched.append(leaf)

# 写入映射文件
try:
    with open('$OUTPUT_MAP_FILE', 'w') as out:
        for base, leaves in mapping.items():
            # 只为那些实际有叶节点匹配的基础物种名写入条目
            if leaves:
                out.write(f'{base}: {",".join(leaves)}\n')
except IOError:
    print("错误: 无法写入输出文件 '$OUTPUT_MAP_FILE'。", file=sys.stderr)
    sys.exit(1)

# 报告未匹配项 (如果有)
if unmatched:
    print("\n⚠️ 警告: 以下叶节点名未能匹配到任何基础物种名:", file=sys.stderr)
    for u in unmatched:
        print(f"  - {u}", file=sys.stderr)
    print("  -> 请检查您的 BASE_NAMES 列表是否完整，或叶节点命名是否符合预期。", file=sys.stderr)

EOF

# 3. 清理临时文件
rm "$LEAF_NAMES_TMP"

echo "✅ ASTRAL 映射文件 '$OUTPUT_MAP_FILE' 已成功生成！"