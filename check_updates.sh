#!/bin/bash

# 仓库及其需要监控的分支，格式: "仓库URL|分支1,分支2,..."
REPOS=(
    "https://github.com/immortalwrt/immortalwrt|openwrt-24.10,openwrt-25.12"
    "https://github.com/immortalwrt/packages|openwrt-24.10,openwrt-25.12"
    "https://github.com/immortalwrt/luci|openwrt-24.10,openwrt-25.12"
    "https://github.com/Openwrt-Passwall/openwrt-passwall|main"
    "https://github.com/Openwrt-Passwall/openwrt-passwall-packages|main"
)

COMMIT_FILE="last_commits.txt"

declare -A LAST_COMMITS
if [[ -f "$COMMIT_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        repo=$(echo "$line" | awk '{print $1}')
        branch=$(echo "$line" | awk '{print $2}')
        commit=$(echo "$line" | awk '{print $3}')
        [[ -z "$repo" || -z "$branch" || -z "$commit" ]] && continue
        LAST_COMMITS["${repo}|${branch}"]="$commit"
    done < "$COMMIT_FILE"
fi

HAS_UPDATE=false
for REPO_ENTRY in "${REPOS[@]}"; do
    REPO="${REPO_ENTRY%%|*}"
    BRANCH_LIST="${REPO_ENTRY#*|}"

    echo "===== 检查仓库: $REPO ====="

    IFS=',' read -ra BRANCHES <<< "$BRANCH_LIST"
    for BRANCH in "${BRANCHES[@]}"; do
        KEY="${REPO}|${BRANCH}"
        echo "检查分支: $BRANCH ..."

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

if [[ "$HAS_UPDATE" == true ]]; then
    > "$COMMIT_FILE"
    for KEY in "${!LAST_COMMITS[@]}"; do
        repo="${KEY%%|*}"
        branch="${KEY#*|}"
        echo "$repo $branch ${LAST_COMMITS[$KEY]}" >> "$COMMIT_FILE"
    done
    echo "🎯 检测到代码更新，需要编译"
    exit 0
else
    echo "⏭️  无代码更新，跳过编译"
    exit 1
fi
