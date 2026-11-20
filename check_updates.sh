#!/bin/bash

# ============================================================
# 1. 仓库及其需要监控的分支，格式: "仓库URL|分支1,分支2,..."
# ============================================================
REPOS=(
    "https://github.com/immortalwrt/immortalwrt|openwrt-24.10,openwrt-25.12"
    "https://github.com/immortalwrt/packages|openwrt-24.10,openwrt-25.12"
    "https://github.com/immortalwrt/luci|openwrt-24.10,openwrt-25.12"
    #"https://github.com/Openwrt-Passwall/openwrt-passwall|main"
)

# ============================================================
# 2. 需要监控 Release（版本发布）的仓库，格式: "owner/repo"
# ============================================================
RELEASE_REPOS=(
    "Openwrt-Passwall/openwrt-passwall"
)

# 存储上次检查的 commit ID 的文件
COMMIT_FILE="last_commits.txt"
# 存储上次 Release 版本的文件
RELEASE_FILE="last_release.txt"

# ============================================================
# 3. 初始化或读取上次的 commit ID
#    文件格式: <repo> <branch> <commit>
# ============================================================
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

# ============================================================
# 4. 读取上次记录的 Release 版本
#    文件格式（每行一条）: <owner/repo> <tag>
# ============================================================
declare -A LAST_RELEASES
if [[ -f "$RELEASE_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        repo=$(echo "$line" | awk '{print $1}')
        tag=$(echo "$line" | awk '{print $2}')
        [[ -z "$repo" || -z "$tag" ]] && continue
        LAST_RELEASES["$repo"]="$tag"
    done < "$RELEASE_FILE"
fi

# ============================================================
# 5. 检查每个仓库、每个分支是否有更新
# ============================================================
HAS_UPDATE=false

for REPO_ENTRY in "${REPOS[@]}"; do
    REPO="${REPO_ENTRY%%|*}"
    BRANCH_LIST="${REPO_ENTRY#*|}"

    echo "===== 检查仓库: $REPO ====="

    IFS=',' read -ra BRANCHES <<< "$BRANCH_LIST"
    for BRANCH in "${BRANCHES[@]}"; do
        KEY="${REPO}|${BRANCH}"
        echo "检查分支: $BRANCH ..."

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

# ============================================================
# 6. 检查每个仓库是否有新的 Release 发布
# ============================================================
for RELEASE_REPO in "${RELEASE_REPOS[@]}"; do
    echo "===== 检查 Release: $RELEASE_REPO ====="

    API_URL="https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
    RESPONSE=$(curl -sL \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent: Release-Monitor" \
        "$API_URL")

    if ! echo "$RESPONSE" | grep -q '"tag_name"'; then
        echo "⚠️  无法获取 ${RELEASE_REPO} 的 Release 信息，跳过（不影响其他检查）"
        echo "   API 返回片段: $(echo "$RESPONSE" | head -c 200)"
        continue
    fi

    LATEST_TAG=$(echo "$RESPONSE" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    OLD_TAG="${LAST_RELEASES[$RELEASE_REPO]}"

    if [[ -z "$OLD_TAG" ]]; then
        echo "🆕 首次记录 Release: $RELEASE_REPO -> $LATEST_TAG"
        HAS_UPDATE=true
        LAST_RELEASES["$RELEASE_REPO"]="$LATEST_TAG"
    elif [[ "$OLD_TAG" != "$LATEST_TAG" ]]; then
        echo "✅ 检测到新版本发布: $RELEASE_REPO"
        echo "   旧版本: $OLD_TAG"
        echo "   新版本: $LATEST_TAG"
        HAS_UPDATE=true
        LAST_RELEASES["$RELEASE_REPO"]="$LATEST_TAG"
    else
        echo "✅ Release 无更新: $RELEASE_REPO ($LATEST_TAG)"
    fi
done

# ============================================================
# 7. 如果有更新，写回记录文件（仅当内容真正变化时才覆盖）
# ============================================================
if [[ "$HAS_UPDATE" == true ]]; then
    # --- 写回 commit 记录（排序保证行序稳定，便于 cmp 比较）---
    TMP_COMMITS=$(mktemp)
    {
        for KEY in "${!LAST_COMMITS[@]}"; do
            repo="${KEY%%|*}"
            branch="${KEY#*|}"
            echo "$repo $branch ${LAST_COMMITS[$KEY]}"
        done
    } | sort > "$TMP_COMMITS"

    if [[ -f "$COMMIT_FILE" ]] && cmp -s "$TMP_COMMITS" "$COMMIT_FILE"; then
        echo "ℹ️  $COMMIT_FILE 内容无变化，未修改"
        rm -f "$TMP_COMMITS"
    else
        mv "$TMP_COMMITS" "$COMMIT_FILE"
        echo "📝 已更新 $COMMIT_FILE"
    fi

    # --- 写回 release 记录（同样排序 + 比较）---
    TMP_RELEASES=$(mktemp)
    {
        for repo in "${!LAST_RELEASES[@]}"; do
            echo "$repo ${LAST_RELEASES[$repo]}"
        done
    } | sort > "$TMP_RELEASES"

    if [[ -f "$RELEASE_FILE" ]] && cmp -s "$TMP_RELEASES" "$RELEASE_FILE"; then
        echo "ℹ️  $RELEASE_FILE 内容无变化，未修改"
        rm -f "$TMP_RELEASES"
    else
        mv "$TMP_RELEASES" "$RELEASE_FILE"
        echo "📝 已更新 $RELEASE_FILE"
    fi

    echo "🎯 检测到代码/版本更新，需要编译"
    exit 0
else
    echo "⏭️  无代码/版本更新，跳过编译"
    exit 1
fi
