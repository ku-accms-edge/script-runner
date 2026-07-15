#!/bin/bash
set -euo pipefail

# =============================================================================
# Git Script Runner - Entrypoint Script
# =============================================================================
# このスクリプトはKubernetes Pod内で実行され、以下の処理を行います:
# 1. ビルドコマンドの実行 (依存関係のインストールなど)
# 2. 指定されたコマンドの実行
#
# 環境変数:
#   GIT_SUBDIR       - リポジトリ内のサブディレクトリ (オプション)
#   BUILD_COMMAND    - SCRIPT_COMMAND の前に実行するビルドコマンド (オプション)
#                      例: "pip install ." / "uv sync" / "npm ci"
#                      "skip" を指定するとビルドステップを完全にスキップ
#                      未指定の場合は pyproject.toml / requirements.txt を自動検出
#   SCRIPT_COMMAND   - 実行するコマンド (必須)
#   PIP_INDEX_URL    - カスタムPyPIインデックス (オプション)
# =============================================================================

export PATH="/workspace/.pip-packages/bin:$PATH"

WORK_DIR="/workspace"
SCRIPT_DIR="${WORK_DIR}"

# サブディレクトリが指定されている場合はそちらに移動
if [[ -n "${GIT_SUBDIR:-}" ]]; then
    SCRIPT_DIR="${WORK_DIR}/${GIT_SUBDIR}"
fi

echo "=========================================="
echo "Git Script Runner - Starting"
echo "=========================================="
echo "Working directory: ${SCRIPT_DIR}"
echo "Command: ${SCRIPT_COMMAND:-<not set>}"
echo ""

# 作業ディレクトリに移動
cd "${SCRIPT_DIR}"

# =============================================================================
# ビルドステップ (依存関係のインストールなど)
# =============================================================================
# BUILD_COMMAND が指定されていればそれを実行する。
# 未指定の場合は Python プロジェクトとして自動検出を試みる。
echo "📦 Build step..."

BUILD_COMMAND="${BUILD_COMMAND:-}"

if [[ "${BUILD_COMMAND}" == "skip" ]]; then
    echo "ℹ️  BUILD_COMMAND=skip - skipping build step"
elif [[ -n "${BUILD_COMMAND}" ]]; then
    echo "🔨 Running build command: ${BUILD_COMMAND}"
    bash -c "${BUILD_COMMAND}"
    echo "✅ Build command completed"
elif command -v pip &> /dev/null; then
    # BUILD_COMMAND 未指定時: pyproject.toml / requirements.txt を自動検出
    pip install --upgrade pip --quiet --root-user-action=ignore

    if [[ -f "pyproject.toml" ]]; then
        echo "Found pyproject.toml - installing project with dependencies..."
        pip install . --quiet --root-user-action=ignore
        echo "✅ Dependencies installed from pyproject.toml"
    elif [[ -f "requirements.txt" ]]; then
        echo "Found requirements.txt - installing dependencies..."
        pip install -r requirements.txt --quiet --root-user-action=ignore
        echo "✅ Dependencies installed from requirements.txt"
    else
        echo "ℹ️  No pyproject.toml or requirements.txt found - skipping dependency installation"
    fi
else
    echo "ℹ️  pip not found - skipping dependency installation"
fi

echo ""

# =============================================================================
# コマンドの実行
# =============================================================================
if [[ -z "${SCRIPT_COMMAND:-}" ]]; then
    echo "❌ Error: SCRIPT_COMMAND environment variable is not set"
    exit 1
fi

echo "=========================================="
echo "🚀 Executing command: ${SCRIPT_COMMAND}"
echo "=========================================="
echo ""

# コマンドを実行
exec bash -c "${SCRIPT_COMMAND}"
