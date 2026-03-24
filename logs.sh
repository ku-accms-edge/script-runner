#!/bin/bash
# =============================================================================
# logs.sh - Kubernetes リソースのログ閲覧ヘルパースクリプト
# =============================================================================
# 使い方:
#   ./logs.sh <overlay-path> [options]
#
# オプション:
#   -f, --follow          ログをリアルタイムで追跡
#   -c, --container NAME  コンテナを指定 (git-clone | script-runner)
#   -p, --previous        前回のPodのログを表示
#   --tail N              直近N行のみ表示
#   -h, --help            ヘルプを表示
#
# 例:
#   ./logs.sh overlays/my-single-job                  # 全コンテナのログ表示
#   ./logs.sh overlays/my-single-job -f               # ログをフォロー
#   ./logs.sh overlays/my-single-job -c git-clone     # initContainerのログのみ
#   ./logs.sh overlays/my-cronjob                     # CronJobの最新Jobのログ
#   ./logs.sh overlays/my-deployment --tail 50         # 直近50行のみ
# =============================================================================
set -euo pipefail

show_help() {
    sed -n '3,21p' "$0" | sed 's/^# \?//'
}

# =============================================================================
# 引数パース
# =============================================================================
OVERLAY_PATH=""
FOLLOW=false
CONTAINER=""
PREVIOUS=false
TAIL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--follow)    FOLLOW=true; shift ;;
        -c|--container) CONTAINER="$2"; shift 2 ;;
        -p|--previous)  PREVIOUS=true; shift ;;
        --tail)         TAIL="$2"; shift 2 ;;
        -h|--help)      show_help; exit 0 ;;
        -*)             echo "Error: Unknown option '$1'"; echo ""; show_help; exit 1 ;;
        *)              OVERLAY_PATH="$1"; shift ;;
    esac
done

if [[ -z "${OVERLAY_PATH}" ]]; then
    echo "Error: overlay-path is required"
    echo ""
    show_help
    exit 1
fi

if [[ ! -d "${OVERLAY_PATH}" ]]; then
    echo "Error: Directory '${OVERLAY_PATH}' does not exist"
    exit 1
fi

# =============================================================================
# リソース種別の検出
# =============================================================================
KUSTOMIZATION_FILE="${OVERLAY_PATH}/kustomization.yaml"
if [[ ! -f "${KUSTOMIZATION_FILE}" ]]; then
    echo "Error: '${KUSTOMIZATION_FILE}' not found"
    exit 1
fi

if grep -q 'base/single-job' "${KUSTOMIZATION_FILE}"; then
    RESOURCE_KIND="Job"
elif grep -q 'base/cronjob' "${KUSTOMIZATION_FILE}"; then
    RESOURCE_KIND="CronJob"
elif grep -q 'base/deployment' "${KUSTOMIZATION_FILE}"; then
    RESOURCE_KIND="Deployment"
else
    echo "Error: Could not detect resource type from '${KUSTOMIZATION_FILE}'"
    echo "       resources に ../../base/single-job, ../../base/cronjob, ../../base/deployment のいずれかを指定してください"
    exit 1
fi

# =============================================================================
# Namespace の取得
# =============================================================================
NAMESPACE=$(grep -E '^\s*namespace:' "${KUSTOMIZATION_FILE}" 2>/dev/null | awk '{print $2}' || echo "")
if [[ -z "${NAMESPACE}" ]]; then
    NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
    [[ -z "${NAMESPACE}" ]] && NAMESPACE="default"
fi

# =============================================================================
# リソース名の取得 (kustomize build から)
# =============================================================================
RESOURCE_NAME=$(kubectl kustomize "${OVERLAY_PATH}" 2>/dev/null \
    | awk "/^kind: ${RESOURCE_KIND}\$/{found=1} found && /^  name:/{print \$2; exit}")

if [[ -z "${RESOURCE_NAME}" ]]; then
    echo "Error: Could not determine resource name from kustomize build"
    exit 1
fi

echo "📋 ${RESOURCE_KIND}: ${RESOURCE_NAME}"
echo "📍 Namespace: ${NAMESPACE}"

# =============================================================================
# CronJob の場合、最新の Job を検索
# =============================================================================
if [[ "${RESOURCE_KIND}" == "CronJob" ]]; then
    LATEST_JOB=$(kubectl get jobs -n "${NAMESPACE}" \
        --sort-by='.metadata.creationTimestamp' \
        -o name 2>/dev/null \
        | grep "${RESOURCE_NAME}" \
        | tail -1 \
        | sed 's|job.batch/||')

    if [[ -z "${LATEST_JOB}" ]]; then
        echo ""
        echo "Error: CronJob '${RESOURCE_NAME}' から生成された Job が見つかりません"
        echo ""
        echo "💡 CronJobがまだ実行されていない可能性があります。手動で実行するには:"
        echo "   kubectl create job --from=cronjob/${RESOURCE_NAME} ${RESOURCE_NAME}-manual -n ${NAMESPACE}"
        exit 1
    fi

    echo "🔄 Latest Job: ${LATEST_JOB}"
    LOG_TARGET="job/${LATEST_JOB}"
else
    case "${RESOURCE_KIND}" in
        Job)        LOG_TARGET="job/${RESOURCE_NAME}" ;;
        Deployment) LOG_TARGET="deployment/${RESOURCE_NAME}" ;;
    esac
fi

echo ""

# =============================================================================
# kubectl logs コマンドの組み立て・実行
# =============================================================================
KUBECTL_ARGS=(-n "${NAMESPACE}")

if [[ -n "${CONTAINER}" ]]; then
    KUBECTL_ARGS+=(-c "${CONTAINER}")
else
    KUBECTL_ARGS+=(--all-containers --prefix)
fi

if [[ "${FOLLOW}" == true ]]; then    KUBECTL_ARGS+=(-f); fi
if [[ "${PREVIOUS}" == true ]]; then  KUBECTL_ARGS+=(--previous); fi
if [[ -n "${TAIL}" ]]; then           KUBECTL_ARGS+=(--tail="${TAIL}"); fi

kubectl logs "${LOG_TARGET}" "${KUBECTL_ARGS[@]}"
