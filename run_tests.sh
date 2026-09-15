#!/bin/bash
# 测试运行器。
#
# 这些测试是**独立可执行文件**，不是 XCTest 套件 —— 项目用 swiftc 手工编译，
# 没有 SwiftPM，引入 XCTest 需要额外的链接配置。所以每个测试自带最小的
# 依赖桩（stub），单独编译运行。
#
# 用法：
#   ./run_tests.sh              # 跑全部
#   ./run_tests.sh SafetyGuard  # 只跑名字匹配的

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources/MacCleaner"
OUT="$ROOT/build/tests"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"
TARGET="arm64-apple-macosx15.0"

mkdir -p "$OUT"

# 每个测试需要的真实源文件（顺序无关，swiftc 自行解析）
sources_for() {
    case "$1" in
        SafetyGuardTests)      echo "$SRC/Services/SafetyGuard.swift" ;;
        DuplicateFinderTests)  echo "$SRC/Scanner/DuplicateFinder.swift" ;;
        AppInventoryTests)     echo "$SRC/Scanner/AppInventory.swift $SRC/Services/SizeCalculator.swift" ;;
        CleanupHistoryTests)   echo "$SRC/Models/CleanupHistory.swift" ;;
        DiskHealthProbeTests)  echo "$SRC/Services/DiskHealthProbe.swift" ;;
        *)                     echo "" ;;
    esac
}

FILTER="${1:-}"
PASS=0
FAIL=0
FAILED_NAMES=()

for test_file in "$ROOT"/Tests/*.swift; do
    name="$(basename "$test_file" .swift)"

    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
        continue
    fi

    # SafetyGuardTests 需要原始版本做对照，单独处理
    extra=""
    if [ "$name" = "SafetyGuardTests" ]; then
        orig="$OUT/SafetyGuardOriginal.swift"
        git -C "$ROOT" show HEAD:Sources/MacCleaner/Services/SafetyGuard.swift 2>/dev/null \
            | sed 's/^enum SafetyGuard {/enum SafetyGuardOrig {/' > "$orig"
        if [ -s "$orig" ]; then extra="$orig"; fi
    fi

    deps="$(sources_for "$name")"
    if [ -z "$deps" ]; then
        echo "⚠️  跳过 $name（未在 sources_for 中登记依赖）"
        continue
    fi

    echo "───────────────────────────────────────────"
    echo "▶ $name"
    echo "───────────────────────────────────────────"

    # 测试文件必须是 main.swift 才能有顶层代码
    work="$(mktemp -d)"
    cp "$test_file" "$work/main.swift"

    if ! swiftc -sdk "$SDK" -target "$TARGET" -o "$work/test" \
         "$work/main.swift" $deps $extra 2>"$work/err"; then
        echo "❌ 编译失败："
        grep -E "error:" "$work/err" | head -10
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name（编译失败）")
        rm -rf "$work"
        continue
    fi

    if "$work/test"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name（断言失败）")
    fi
    rm -rf "$work"
    echo
done

echo "═══════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
    echo "✅ 全部通过（$PASS 个测试文件）"
else
    echo "❌ $FAIL 个失败，$PASS 个通过"
    for n in "${FAILED_NAMES[@]}"; do echo "   · $n"; done
fi
echo "═══════════════════════════════════════════"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
