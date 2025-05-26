INPUT_RENAMED_TREES_FILE="nc_species_mapped.tre" # 使用您重命名后的 ML 树
OUTPUT_SPECIES_PP_TREE="astral_species_pp.tre"   # 新的输出文件名
ASTRAL_JAVA_MEMORY="4G" # 或者您需要的内存
ASTRAL_CONTAINER="/usr/local/biotools/a/astral-tree:5.7.8--hdfd78af_0"
OUTGROUP_NAME="Drosophila_melanogaster"

echo "--- 运行 ASTRAL 获取 LPP 支持度 ---"
singularity exec --env _JAVA_OPTIONS=\"-Xmx${ASTRAL_JAVA_MEMORY}\" \
    "$ASTRAL_CONTAINER" \
    astral \
    -i "$INPUT_RENAMED_TREES_FILE" \
    -o "$OUTPUT_SPECIES_PP_TREE" \
    --outgroup "$OUTGROUP_NAME" 2> astral_pp.log 

# 检查是否成功
if [ $? -ne 0 ]; then
    echo "错误：ASTRAL (LPP) 运行失败！请检查 astral_pp.log。"
    exit 1
fi
echo "✅ ASTRAL (LPP) 运行成功，结果保存在 $OUTPUT_SPECIES_PP_TREE"