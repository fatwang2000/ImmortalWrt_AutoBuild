#!/bin/bash

REPOS=(
    "https://github.com/immortalwrt/immortalwrt"
    "https://github.com/immortalwrt/packages"
    "https://github.com/immortalwrt/luci"
)
BRANCH="openwrt-24.10"

# 存储上次检查的 commit ID 的文件
COMMIT_FILE="last_commits.txt"

# 初始化或读取上次的 commit ID
declare -A LAST_COMMITS
if [[ -f "$COMMIT_FILE" ]]; then
    while IFS= read -r line; do
        repo=$(echo "$line" | cut -d' ' -f1)
        commit=$(echo "$line" | cut -d' ' -f2)
        LAST_COMMITS["$repo"]=$commit
    done < "$COMMIT_FILE"
fi

# 检查每个仓库是否有更新
HAS_UPDATE=false
for REPO in "${REPOS[@]}"; do
    echo "Checking $REPO ..."
    # 获取远程分支的最新 commit ID
    LATEST_COMMIT=$(git ls-remote "$REPO" "refs/heads/$BRANCH" | cut -f1)
    if [[ -z "$LATEST_COMMIT" ]]; then
        echo "Error: Failed to get commit ID for $REPO"
        exit 1
    fi

    # 与上次记录的 commit ID 比较
    if [[ "${LAST_COMMITS["$REPO"]}" != "$LATEST_COMMIT" ]]; then
        echo "Update detected in $REPO"
        HAS_UPDATE=true
        # 更新记录
        LAST_COMMITS["$REPO"]="$LATEST_COMMIT"
    else
        echo "No update in $REPO"
    fi
done

# 如果有更新，则更新 commit 记录文件并返回成功（触发编译）
if [[ "$HAS_UPDATE" == true ]]; then
    # 写入新的 commit ID
    > "$COMMIT_FILE"  # 清空文件
    for REPO in "${REPOS[@]}"; do
        echo "$REPO ${LAST_COMMITS["$REPO"]}" >> "$COMMIT_FILE"
    done
    echo "Changes detected, triggering build."
    exit 0
else
    echo "No changes, skipping build."
    exit 1
fi
