#!/bin/bash
set -euo pipefail

# =============================================================================
# Git Script Runner - Entrypoint Script
# =============================================================================
# このスクリプトはKubernetes Pod内で実行され、以下の処理を行います:
# 1. 依存関係のインストール (requirements.txt または pyproject.toml)
# 2. 指定されたコマンドの実行
#
# 環境変数:
#   GIT_SUBDIR       - リポジトリ内のサブディレクトリ (オプション)
#   SCRIPT_COMMAND   - 実行するコマンド (必須)
#   PIP_INDEX_URL    - カスタムPyPIインデックス (オプション)
# =============================================================================

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
# 依存関係のインストール
# =============================================================================
echo "📦 Checking for dependencies..."

# pipのアップグレード
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

# コマンドを実行 (シェル展開を有効にするためevalを使用)
exec bash -c "${SCRIPT_COMMAND}"
