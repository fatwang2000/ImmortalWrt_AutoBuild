#!/bin/bash

REPOS=(
    "https://github.com/immortalwrt/immortalwrt"
    "https://github.com/immortalwrt/packages"
    "https://github.com/immortalwrt/luci"
)

# 需要检查的分支列表
BRANCHES=(
    "openwrt-24.10"
    "openwrt-25.12"
)

# 存储上次检查的 commit ID 的文件
COMMIT_FILE="last_commits.txt"

# 初始化或读取上次的 commit ID
# 文件格式: <repo> <branch> <commit>
declare -A LAST_COMMITS
if [[ -f "$COMMIT_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        repo=$(echo "$line" | awk '{print $1}')
        branch=$(echo "$line" | awk '{print $2}')
        commit=$(echo "$line" | awk '{print $3}')
        [[ -z "$repo" || -z "$branch" || -z "$commit" ]] && continue
        LAST_COMMITS["${repo}:${branch}"]="$commit"
    done < "$COMMIT_FILE"
fi

# 检查每个仓库、每个分支是否有更新
HAS_UPDATE=false
for BRANCH in "${BRANCHES[@]}"; do
    echo "===== 检查分支: $BRANCH ====="
    for REPO in "${REPOS[@]}"; do
        KEY="${REPO}:${BRANCH}"
        echo "检查仓库: $REPO ($BRANCH) ..."

        # 用 --exit-code 区分 “分支不存在(2)” 和 “网络/仓库错误(其它非0)”
        LS_OUT=$(git ls-remote --exit-code "$REPO" "refs/heads/$BRANCH" 2>/dev/null)
        RC=$?

        if [[ $RC -eq 2 ]]; then
            echo "⚠️  分支 $BRANCH 不存在，跳过: $REPO"
            continue
        elif [[ $RC -ne 0 ]]; then
            echo "❌ 错误: 无法访问 $REPO (exit=$RC)"
            exit 1
        fi

        LATEST_COMMIT=$(echo "$LS_OUT" | cut -f1)
        if [[ -z "$LATEST_COMMIT" ]]; then
            echo "❌ 错误: 无法获取 $REPO 的 $BRANCH commit ID"
            exit 1
        fi

        OLD_COMMIT="${LAST_COMMITS[$KEY]}"

        if [[ -z "$OLD_COMMIT" ]]; then
            # 首次记录（新分支或首次运行）
            echo "🆕 首次记录: $REPO ($BRANCH)"
            echo "   commit: $LATEST_COMMIT"
            HAS_UPDATE=true
            LAST_COMMITS["$KEY"]="$LATEST_COMMIT"
        elif [[ "$OLD_COMMIT" != "$LATEST_COMMIT" ]]; then
            echo "✅ 检测到更新: $REPO ($BRANCH)"
            echo "   旧 commit: $OLD_COMMIT"
            echo "   新 commit: $LATEST_COMMIT"
            HAS_UPDATE=true
            LAST_COMMITS["$KEY"]="$LATEST_COMMIT"
        else
            echo "✅ 无更新: $REPO ($BRANCH)"
        fi
    done
done

# 如果有更新，则更新 commit 记录文件并返回成功（触发编译）
if [[ "$HAS_UPDATE" == true ]]; then
    > "$COMMIT_FILE"  # 清空文件
    for KEY in "${!LAST_COMMITS[@]}"; do
        repo="${KEY%%:*}"      # 第一个冒号前
        branch="${KEY#*:}"     # 第一个冒号后
        echo "$repo $branch ${LAST_COMMITS[$KEY]}" >> "$COMMIT_FILE"
    done
    echo "🎯 检测到代码更新，需要编译"
    exit 0
else
    echo "⏭️  无代码更新，跳过编译"
    exit 1
fi
