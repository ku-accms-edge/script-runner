#!/bin/bash
# =============================================================================
# Script Runner セットアップヘルパー
# =============================================================================
# Kubernetes上でPythonスクリプトを実行するための設定を対話的に作成します。
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 定数・色定義
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAYS_DIR="${SCRIPT_DIR}/overlays"

# 色コード (端末が対応していない場合は無効化)
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  GREEN=$(tput setaf 2)
  CYAN=$(tput setaf 6)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
  DIM=$(tput dim)
else
  BOLD="" RESET="" GREEN="" CYAN="" YELLOW="" RED="" DIM=""
fi

# ---------------------------------------------------------------------------
# ユーティリティ関数
# ---------------------------------------------------------------------------

# 罫線を表示
line() {
  echo "${DIM}$(printf '%.0s─' {1..60})${RESET}"
}

# セクションヘッダーを表示
section() {
  echo ""
  line
  echo "${BOLD}${CYAN}  $1${RESET}"
  line
}

# 情報メッセージ
info() {
  echo "  ${DIM}$1${RESET}"
}

# 成功メッセージ
success() {
  echo "${GREEN}  ✔ $1${RESET}"
}

# 警告メッセージ
warn() {
  echo "${YELLOW}  ⚠ $1${RESET}"
}

# エラーメッセージ
error() {
  echo "${RED}  ✘ $1${RESET}"
}

# プロンプト表示 (引数: ラベル, デフォルト値)
# 結果は REPLY 変数に格納
prompt() {
  local label="$1"
  local default="${2:-}"

  if [[ -n "$default" ]]; then
    printf "\n  ${BOLD}%s${RESET} ${DIM}(デフォルト: %s)${RESET}\n  > " "$label" "$default"
  else
    printf "\n  ${BOLD}%s${RESET}\n  > " "$label"
  fi
  read -r REPLY
  REPLY="${REPLY:-$default}"
}

# Yes/No プロンプト (引数: ラベル, デフォルト y/n)
# 戻り値: 0=yes, 1=no
confirm() {
  local label="$1"
  local default="${2:-n}"
  local hint

  if [[ "$default" == "y" ]]; then
    hint="Y/n"
  else
    hint="y/N"
  fi

  printf "\n  ${BOLD}%s${RESET} [%s] " "$label" "$hint"
  read -r REPLY
  REPLY="${REPLY:-$default}"

  case "$REPLY" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# 番号選択プロンプト (引数: ラベル, 選択肢の配列名)
# 結果は SELECTED_INDEX (0始まり) と SELECTED_VALUE に格納
select_option() {
  local label="$1"
  shift
  local options=("$@")

  echo ""
  echo "  ${BOLD}${label}${RESET}"
  echo ""

  local i
  for i in "${!options[@]}"; do
    echo "    ${BOLD}$((i + 1))${RESET}) ${options[$i]}"
  done

  while true; do
    printf "\n  番号を入力してください > "
    read -r REPLY

    if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#options[@]} )); then
      SELECTED_INDEX=$((REPLY - 1))
      SELECTED_VALUE="${options[$SELECTED_INDEX]}"
      return 0
    else
      error "1〜${#options[@]} の番号を入力してください"
    fi
  done
}

# ---------------------------------------------------------------------------
# バリデーション関数
# ---------------------------------------------------------------------------

validate_overlay_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    error "名前を入力してください"
    return 1
  fi
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    error "英小文字・数字・ハイフン・ドットのみ使用できます (先頭は英小文字または数字)"
    return 1
  fi
  if [[ -d "${OVERLAYS_DIR}/${name}" ]]; then
    error "overlays/${name} は既に存在します。別の名前を指定してください"
    return 1
  fi
  return 0
}

validate_namespace() {
  local ns="$1"
  if [[ -z "$ns" ]]; then
    error "namespaceを入力してください"
    return 1
  fi
  if [[ ! "$ns" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    error "英小文字・数字・ハイフンのみ使用できます"
    return 1
  fi
  return 0
}

validate_name_prefix() {
  local prefix="$1"
  if [[ -z "$prefix" ]]; then
    error "プレフィックスを入力してください"
    return 1
  fi
  if [[ ! "$prefix" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    error "英小文字・数字・ハイフンのみ使用できます"
    return 1
  fi
  return 0
}

validate_git_url() {
  local url="$1"
  if [[ -z "$url" ]]; then
    error "URLを入力してください"
    return 1
  fi
  if [[ ! "$url" =~ ^https://.*\.git$ ]]; then
    warn "通常は https://.../*.git 形式のURLを指定します"
    if ! confirm "このURLで続行しますか？"; then
      return 1
    fi
  fi
  return 0
}

validate_cron_schedule() {
  local schedule="$1"
  if [[ -z "$schedule" ]]; then
    error "スケジュールを入力してください"
    return 1
  fi
  # 簡易的なcron式チェック (5フィールド)
  local fields
  fields=$(echo "$schedule" | wc -w)
  if [[ "$fields" -ne 5 ]]; then
    error "cron式は5つのフィールドが必要です (分 時 日 月 曜日)"
    return 1
  fi
  return 0
}

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    error "1〜65535 の数値を入力してください"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# テンプレート編集用ヘルパー関数
# ---------------------------------------------------------------------------
# サンプルオーバーレイをコピーし、sed で値を書き換える方式。
# サンプルが更新されても setup.sh との不整合が起きない。
# ---------------------------------------------------------------------------

# sed 置換文字列のエスケープ (& \ | をエスケープ)
sed_escape() {
  printf '%s' "$1" | sed 's/[&\\/|]/\\&/g'
}

# configMapGenerator の値を置換
# Usage: replace_config_value <file> <KEY> <value>
replace_config_value() {
  local file="$1" key="$2" value
  value=$(sed_escape "$3")
  sed -i "s|- ${key}=.*|- ${key}=${value}|" "$file"
}

# コメントアウトされた行を有効化 (最初の '# ' を除去)
# Usage: uncomment_line <file> <grep正規表現>
uncomment_line() {
  local file="$1" pattern="$2"
  sed -i "/${pattern}/s/# //" "$file"
}

# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

main() {
  echo ""
  echo "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
  echo "${BOLD}${GREEN}  ║       Script Runner セットアップヘルパー            ║${RESET}"
  echo "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
  info "このツールは、KubernetesでPythonスクリプトを実行するための"
  info "設定ファイルを対話的に作成します。"
  info "いくつかの質問に答えるだけで、必要なファイルが自動生成されます。"

  # =========================================================================
  # Step 1: 実行タイプの選択
  # =========================================================================
  section "Step 1/5: 実行タイプの選択"

  info "スクリプトをどのように実行しますか？"

  local type_options=(
    "Job (1回だけ実行)         - バッチ処理、データ変換など"
    "CronJob (定期的に実行)    - 日次レポート、定期同期など"
    "Deployment (常時起動)     - APIサーバー、常駐サービスなど"
  )
  select_option "実行タイプを選んでください:" "${type_options[@]}"

  local exec_types=("single-job" "cronjob" "deployment")
  CFG_EXEC_TYPE="${exec_types[$SELECTED_INDEX]}"

  success "実行タイプ: ${CFG_EXEC_TYPE}"

  # =========================================================================
  # Step 2: 基本設定
  # =========================================================================
  section "Step 2/5: 基本設定"

  # --- オーバーレイ名 ---
  info "作成する設定の名前を決めてください。"
  info "overlays/<名前> ディレクトリが作成されます。"

  while true; do
    prompt "設定名 (英小文字・数字・ハイフン)" "my-${CFG_EXEC_TYPE}"
    CFG_OVERLAY_NAME="$REPLY"
    validate_overlay_name "$CFG_OVERLAY_NAME" && break
  done

  success "設定名: ${CFG_OVERLAY_NAME}"

  # --- Namespace ---
  info "デプロイ先のKubernetes namespaceを指定してください。"

  while true; do
    prompt "Namespace" "default"
    CFG_NAMESPACE="$REPLY"
    validate_namespace "$CFG_NAMESPACE" && break
  done

  success "Namespace: ${CFG_NAMESPACE}"

  # --- namePrefix ---
  info "リソース名の先頭に付けるプレフィックスを指定してください。"
  info "例: 'myapp' → 'myapp-script-runner' というリソース名になります。"

  while true; do
    prompt "プレフィックス" "${CFG_OVERLAY_NAME}"
    CFG_NAME_PREFIX="$REPLY"
    validate_name_prefix "$CFG_NAME_PREFIX" && break
  done

  success "プレフィックス: ${CFG_NAME_PREFIX}"

  # =========================================================================
  # Step 3: Gitリポジトリ設定
  # =========================================================================
  section "Step 3/5: Gitリポジトリの設定"

  info "実行したいPythonスクリプトが格納されているGitリポジトリの情報を"
  info "入力してください。"

  # --- Git URL ---
  while true; do
    prompt "GitリポジトリのURL (https://...*.git)"
    CFG_GIT_URL="$REPLY"
    validate_git_url "$CFG_GIT_URL" && break
  done

  success "リポジトリ: ${CFG_GIT_URL}"

  # --- Git Branch ---
  prompt "ブランチ名" "main"
  CFG_GIT_BRANCH="$REPLY"
  success "ブランチ: ${CFG_GIT_BRANCH}"

  # --- Git Subdir ---
  info "スクリプトがリポジトリのサブディレクトリにある場合は指定してください。"
  info "ルート直下にある場合は空のままEnterを押してください。"

  prompt "サブディレクトリ (例: src/scripts)" ""
  CFG_GIT_SUBDIR="$REPLY"

  if [[ -n "$CFG_GIT_SUBDIR" ]]; then
    success "サブディレクトリ: ${CFG_GIT_SUBDIR}"
  else
    success "サブディレクトリ: (なし - ルート直下)"
  fi

  # --- Private repo ---
  CFG_PRIVATE_REPO="n"
  if confirm "プライベートリポジトリですか？ (認証トークンが必要)"; then
    CFG_PRIVATE_REPO="y"
    warn "secret.yaml が生成されます。デプロイ前にトークンを設定してください。"
  fi

  # =========================================================================
  # Step 4: スクリプト実行設定
  # =========================================================================
  section "Step 4/5: スクリプトの実行設定"

  # --- Script Command ---
  info "コンテナ内で実行するコマンドを指定してください。"

  case "$CFG_EXEC_TYPE" in
    single-job)
      info "例: python main.py"
      info "例: python main.py --config config.yaml"
      ;;
    cronjob)
      info "例: python main.py"
      info "例: python report.py --output /tmp/report.csv"
      ;;
    deployment)
      info "例: python -m uvicorn main:app --host 0.0.0.0 --port 8080"
      info "例: python server.py"
      ;;
  esac

  while true; do
    prompt "実行コマンド" "python main.py"
    CFG_SCRIPT_COMMAND="$REPLY"
    if [[ -n "$CFG_SCRIPT_COMMAND" ]]; then
      break
    fi
    error "コマンドを入力してください"
  done

  success "コマンド: ${CFG_SCRIPT_COMMAND}"

  # --- タイプ固有の設定 ---

  # CronJob: スケジュール
  CFG_CRON_SCHEDULE=""
  if [[ "$CFG_EXEC_TYPE" == "cronjob" ]]; then
    echo ""
    info "cron式でスケジュールを指定してください。"
    info "書式: 分 時 日 月 曜日"
    echo ""
    info "よく使われる例:"
    info "  毎日 午前9時:          0 9 * * *"
    info "  平日 午前9時:          0 9 * * 1-5"
    info "  毎時:                  0 * * * *"
    info "  毎日 深夜0時:          0 0 * * *"
    info "  毎週月曜 午前6時:      0 6 * * 1"

    while true; do
      prompt "cron スケジュール" "0 9 * * 1-5"
      CFG_CRON_SCHEDULE="$REPLY"
      validate_cron_schedule "$CFG_CRON_SCHEDULE" && break
    done

    success "スケジュール: ${CFG_CRON_SCHEDULE}"
  fi

  # Deployment: Service & ポート設定
  CFG_USE_SERVICE="n"
  CFG_CONTAINER_PORT=""
  CFG_SERVICE_PORT=""
  if [[ "$CFG_EXEC_TYPE" == "deployment" ]]; then
    echo ""
    info "Serviceを作成すると、他のPodやクラスタ内からアクセスできます。"

    if confirm "Serviceリソースを作成しますか？"; then
      CFG_USE_SERVICE="y"

      info "アプリケーションがリッスンするポート番号を指定してください。"

      while true; do
        prompt "コンテナのポート番号" "8080"
        CFG_CONTAINER_PORT="$REPLY"
        validate_port "$CFG_CONTAINER_PORT" && break
      done

      while true; do
        prompt "Serviceの公開ポート番号 (クラスタ内からアクセスする際のポート)" "80"
        CFG_SERVICE_PORT="$REPLY"
        validate_port "$CFG_SERVICE_PORT" && break
      done

      success "コンテナポート: ${CFG_CONTAINER_PORT}, 公開ポート: ${CFG_SERVICE_PORT}"
    fi
  fi

  # =========================================================================
  # Step 5: 確認・生成
  # =========================================================================
  section "Step 5/5: 設定内容の確認"

  echo ""
  echo "  ${BOLD}設定内容:${RESET}"
  echo ""
  echo "  実行タイプ:        ${BOLD}${CFG_EXEC_TYPE}${RESET}"
  echo "  出力先:            ${BOLD}overlays/${CFG_OVERLAY_NAME}/${RESET}"
  echo "  Namespace:         ${BOLD}${CFG_NAMESPACE}${RESET}"
  echo "  プレフィックス:    ${BOLD}${CFG_NAME_PREFIX}${RESET}"
  echo "  GitリポジトリURL:  ${BOLD}${CFG_GIT_URL}${RESET}"
  echo "  ブランチ:          ${BOLD}${CFG_GIT_BRANCH}${RESET}"

  if [[ -n "$CFG_GIT_SUBDIR" ]]; then
    echo "  サブディレクトリ:  ${BOLD}${CFG_GIT_SUBDIR}${RESET}"
  fi

  echo "  実行コマンド:      ${BOLD}${CFG_SCRIPT_COMMAND}${RESET}"
  echo "  プライベートリポ:  ${BOLD}$([ "$CFG_PRIVATE_REPO" = "y" ] && echo "はい" || echo "いいえ")${RESET}"

  if [[ "$CFG_EXEC_TYPE" == "cronjob" ]]; then
    echo "  スケジュール:      ${BOLD}${CFG_CRON_SCHEDULE}${RESET}"
  fi

  if [[ "$CFG_EXEC_TYPE" == "deployment" ]]; then
    echo "  Service作成:       ${BOLD}$([ "$CFG_USE_SERVICE" = "y" ] && echo "はい (${CFG_SERVICE_PORT} → ${CFG_CONTAINER_PORT})" || echo "いいえ")${RESET}"
  fi

  echo ""

  if ! confirm "この内容でファイルを生成しますか？" "y"; then
    warn "キャンセルしました。"
    exit 0
  fi

  # =========================================================================
  # ファイル生成 (サンプルオーバーレイをコピーして編集)
  # =========================================================================
  echo ""
  local example_dir="${OVERLAYS_DIR}/example-${CFG_EXEC_TYPE}"
  local output_dir="${OVERLAYS_DIR}/${CFG_OVERLAY_NAME}"
  local kustomization="${output_dir}/kustomization.yaml"

  # サンプルオーバーレイをコピー
  cp -r "$example_dir" "$output_dir"

  # secret.yaml.example は不要なので削除
  rm -f "${output_dir}/secret.yaml.example"

  # --- kustomization.yaml の共通設定を書き換え ---
  sed -i "s|^namespace: .*|namespace: ${CFG_NAMESPACE}|" "$kustomization"
  sed -i "s|^namePrefix: .*|namePrefix: ${CFG_NAME_PREFIX}-|" "$kustomization"

  replace_config_value "$kustomization" "GIT_REPO_URL" "$CFG_GIT_URL"
  replace_config_value "$kustomization" "GIT_BRANCH" "$CFG_GIT_BRANCH"
  replace_config_value "$kustomization" "GIT_SUBDIR" "$CFG_GIT_SUBDIR"
  replace_config_value "$kustomization" "SCRIPT_COMMAND" "$CFG_SCRIPT_COMMAND"

  # --- プライベートリポジトリ ---
  if [[ "$CFG_PRIVATE_REPO" == "y" ]]; then
    sed -i 's|^  # - secret.yaml|  - secret.yaml|' "$kustomization"
    cp "${example_dir}/secret.yaml.example" "${output_dir}/secret.yaml"
  fi

  # --- CronJob: スケジュール ---
  if [[ "$CFG_EXEC_TYPE" == "cronjob" ]]; then
    sed -i "s|schedule: \".*\"|schedule: \"${CFG_CRON_SCHEDULE}\"|" "$kustomization"
  fi

  # --- Deployment: Service & ポート ---
  if [[ "$CFG_EXEC_TYPE" == "deployment" ]]; then
    if [[ "$CFG_USE_SERVICE" == "y" ]]; then
      local patch_file="${output_dir}/deployment-patch.yaml"
      local service_file="${output_dir}/service.yaml"

      # kustomization.yaml で service.yaml を有効化
      sed -i 's|^  # - service.yaml|  - service.yaml|' "$kustomization"

      # deployment-patch.yaml のポート設定をアンコメント
      uncomment_line "$patch_file" "# ports:"
      uncomment_line "$patch_file" "#.*- name: http"
      uncomment_line "$patch_file" "#.*containerPort:"
      uncomment_line "$patch_file" "#.*protocol: TCP"

      # ポート番号を設定
      sed -i "s|containerPort: .*|containerPort: ${CFG_CONTAINER_PORT}|" "$patch_file"
      sed -i "s|^\([[:space:]]*\)port: .*|\1port: ${CFG_SERVICE_PORT}|" "$service_file"
      sed -i "s|targetPort: .*|targetPort: ${CFG_CONTAINER_PORT}|" "$service_file"
    else
      # Service を使わない場合は service.yaml を削除
      rm -f "${output_dir}/service.yaml"
    fi
  fi

  # =========================================================================
  # 完了メッセージ
  # =========================================================================
  echo ""
  echo "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗${RESET}"
  echo "${BOLD}${GREEN}  ║              セットアップ完了!                      ║${RESET}"
  echo "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""

  echo "  ${BOLD}生成されたファイル:${RESET}"
  for f in "${output_dir}"/*; do
    echo "    ${GREEN}✔${RESET} overlays/${CFG_OVERLAY_NAME}/$(basename "$f")"
  done

  echo ""
  line

  if [[ "$CFG_PRIVATE_REPO" == "y" ]]; then
    echo ""
    echo "  ${YELLOW}${BOLD}次のステップ:${RESET}"
    echo ""
    echo "  ${BOLD}1.${RESET} secret.yaml にGitHubトークンを設定:"
    echo "     ${DIM}vim overlays/${CFG_OVERLAY_NAME}/secret.yaml${RESET}"
    echo ""
    echo "     トークンの作成方法: https://github.com/settings/tokens"
    echo "     ${DIM}Fine-grained token で Contents の Read-only 権限のみ付与を推奨${RESET}"
    echo ""
    echo "  ${BOLD}2.${RESET} デプロイ:"
  else
    echo ""
    echo "  ${YELLOW}${BOLD}次のステップ:${RESET}"
    echo ""
    echo "  ${BOLD}デプロイ:${RESET}"
  fi

  case "$CFG_EXEC_TYPE" in
    single-job)
      echo "     ${CYAN}kubectl apply -k overlays/${CFG_OVERLAY_NAME}${RESET}"
      echo ""
      echo "  ${BOLD}再実行する場合:${RESET}"
      echo "     ${CYAN}./del-and-run-single-job.sh overlays/${CFG_OVERLAY_NAME}${RESET}"
      echo ""
      echo "  ${BOLD}ログの確認:${RESET}"
      echo "     ${CYAN}kubectl logs -n ${CFG_NAMESPACE} job/${CFG_NAME_PREFIX}-script-runner${RESET}"
      ;;
    cronjob)
      echo "     ${CYAN}kubectl apply -k overlays/${CFG_OVERLAY_NAME}${RESET}"
      echo ""
      echo "  ${BOLD}状態の確認:${RESET}"
      echo "     ${CYAN}kubectl get cronjob -n ${CFG_NAMESPACE}${RESET}"
      echo ""
      echo "  ${BOLD}手動で即時実行:${RESET}"
      echo "     ${CYAN}kubectl create job --from=cronjob/${CFG_NAME_PREFIX}-script-runner manual-run -n ${CFG_NAMESPACE}${RESET}"
      ;;
    deployment)
      echo "     ${CYAN}kubectl apply -k overlays/${CFG_OVERLAY_NAME}${RESET}"
      echo ""
      echo "  ${BOLD}状態の確認:${RESET}"
      echo "     ${CYAN}kubectl get pods -n ${CFG_NAMESPACE}${RESET}"
      echo ""
      echo "  ${BOLD}ログの確認:${RESET}"
      echo "     ${CYAN}kubectl logs -n ${CFG_NAMESPACE} -l app.kubernetes.io/name=script-runner --tail=50${RESET}"
      ;;
  esac

  echo ""
  info "設定を変更したい場合は overlays/${CFG_OVERLAY_NAME}/ 内のファイルを"
  info "直接編集してください。"
  echo ""
}

# エントリポイント
main "$@"
