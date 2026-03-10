#!/bin/bash
# =============================================================================
# del-and-run-single-job.sh - Jobを削除後に実行するヘルパースクリプト
# =============================================================================
# 使い方:
#   ./del-and-run-single-job.sh <overlay-path>
#
# 例:
#   ./del-and-run-single-job.sh overlays/my-single-job           # 実行
# =============================================================================
set -euo pipefail

OVERLAY_PATH="${1:-}"
WATCH="${2:-}"

if [[ -z "${OVERLAY_PATH}" ]]; then
    echo "Usage: $0 <overlay-path>"
    echo ""
    echo "Examples:"
    echo "  $0 overlays/my-single-job"
    exit 1
fi

if [[ ! -d "${OVERLAY_PATH}" ]]; then
    echo "Error: Directory '${OVERLAY_PATH}' does not exist"
    exit 1
fi

# Namespaceを取得 (kustomization.yamlから、またはデフォルト)
NAMESPACE=$(grep -E '^\s*namespace:' "${OVERLAY_PATH}/kustomization.yaml" 2>/dev/null | awk '{print $2}' || echo "")
if [[ -z "${NAMESPACE}" ]]; then
    NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
    [[ -z "${NAMESPACE}" ]] && NAMESPACE="default"
fi

echo "🗑️  Jobを削除しています (存在しない場合はスキップします)..."
kubectl delete -k "${OVERLAY_PATH}" --ignore-not-found=true

echo ""
echo "🚀 新しいJobを作成しています..."
# applyの出力からJob名を取得
# 形式1: job.batch/example-script-runner created
# 形式2: job.batch "example-script-runner" created
APPLY_OUTPUT=$(kubectl apply -k "${OVERLAY_PATH}" 2>&1)
echo "${APPLY_OUTPUT}"

# 両方の形式に対応
JOB_NAME=$(echo "${APPLY_OUTPUT}" | grep -E 'job\.batch' | head -1 | sed -E 's/.*job\.batch[/"[:space:]]+([^"[:space:]]+).*/\1/')

if [[ -z "${JOB_NAME}" ]]; then
    echo "Warning: Could not determine Job name"
    exit 0
fi

echo ""
echo "📋 Job: ${JOB_NAME}"
echo "📍 Namespace: ${NAMESPACE}"

echo ""
echo "💡 Commands:"
echo "   ステータス確認: kubectl get job ${JOB_NAME} -n ${NAMESPACE}"
echo "   ログ表示:       kubectl logs -l job-name=${JOB_NAME} -n ${NAMESPACE} --all-containers"
echo "   Job削除:        kubectl delete job ${JOB_NAME} -n ${NAMESPACE}"