# Git Script Runner for Kubernetes

Gitリポジトリから直接Pythonスクリプトを実行するためのKubernetesマニフェスト集です。

コンテナイメージをビルドすることなく、環境変数でGitリポジトリのURLと実行コマンドを指定するだけで、任意のPythonスクリプトをKubernetes Job、CronJob、または Deployment + Service として実行できます。

## 特徴

- **ビルド不要**: 公式のPythonイメージとalpine/gitイメージを使用
- **柔軟な設定**: Kustomizeで環境ごとの設定を簡単に管理
- **Job / CronJob / Deployment 対応**: 一度きりの実行、定期実行、常駐サービスに対応
- **Private リポジトリ対応**: GitHub Personal Access Token による認証をサポート
- **依存関係の自動インストール**: `requirements.txt` と `pyproject.toml` の両方に対応

---

## クイックスタート

### Job (一度きりの実行) の場合
#### 1. リポジトリをクローン

```bash
git clone https://github.com/XXX/git-script-runner.git
cd git-script-runner
```

#### 2. オーバーレイを作成

```bash
cp -r overlays/example-single-job overlays/my-single-job
```

#### 3. 設定をカスタマイズ

`overlays/my-single-job/kustomization.yaml` を編集:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-namespace  # 実行するnamespace

resources:
  - ../../base/single-job

namePrefix: my-job-  # リソース名のプレフィックス

configMapGenerator:
  - name: script-runner-config
    behavior: replace
    literals:
      - GIT_REPO_URL=https://github.com/your-org/your-scripts.git
      - GIT_BRANCH=main
      - SCRIPT_COMMAND=python main.py --arg1 value1
```

#### 4. 実行

```bash
# dry-run で確認
kubectl apply -k overlays/my-single-job --dry-run=client -o yaml

# 実際にデプロイ
kubectl apply -k overlays/my-single-job
```

または，削除後に実行を行うスクリプトで実行

```bash
# スクリプトの実行権限付与，初回のみ
chmod +x ./del-and-run-single-job.sh

# 実行
./del-and-run-single-job.sh overlays/my-single-job
```

#### 5. 削除

```bash
kubectl delete -k overlays/my-single-job
```

---

### CronJob (定期実行) の場合
#### 1. リポジトリをクローン

```bash
git clone https://github.com/XXX/git-script-runner.git
cd git-script-runner
```

#### 2. オーバーレイを作成

```bash
cp -r overlays/example-cronjob overlays/my-cronjob
```

#### 3. 設定をカスタマイズ

`overlays/my-cronjob/kustomization.yaml` を編集:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-namespace  # 実行するnamespace

resources:
  - ../../base/cronjob

namePrefix: my-cronjob-  # リソース名のプレフィックス

configMapGenerator:
  - name: script-runner-config
    behavior: replace
    literals:
      - GIT_REPO_URL=https://github.com/your-org/your-scripts.git
      - GIT_BRANCH=main
      - SCRIPT_COMMAND=python main.py --arg1 value1

patches:
  # [必須] スケジュールを設定
  - patch: |-
      apiVersion: batch/v1
      kind: CronJob
      metadata:
        name: script-runner
      spec:
        schedule: "0 9 * * 1-5"  # 平日9時に実行
```

#### 4. 実行

```bash
# dry-run で確認
kubectl apply -k overlays/my-cronjob --dry-run=client -o yaml

# 実際にデプロイ
kubectl apply -k overlays/my-cronjob
```


#### 5. 削除

```bash
kubectl delete -k overlays/my-cronjob
```

---

### Deployment (常駐サービス) の場合
#### 1. リポジトリをクローン

```bash
git clone https://github.com/XXX/git-script-runner.git
cd git-script-runner
```

#### 2. オーバーレイを作成

```bash
cp -r overlays/example-deployment overlays/my-deployment
```

#### 3. 設定をカスタマイズ

`overlays/my-deployment/kustomization.yaml` を編集:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-namespace  # 実行するnamespace

resources:
  - ../../base/deployment
  - service.yaml  # Service が不要な場合はこの行を削除

namePrefix: my-app-  # リソース名のプレフィックス

configMapGenerator:
  - name: script-runner-config
    behavior: replace
    literals:
      - GIT_REPO_URL=https://github.com/your-org/your-scripts.git
      - GIT_BRANCH=main
      - SCRIPT_COMMAND=python -m uvicorn main:app --host 0.0.0.0 --port 8080
```

Service はオプションです。不要な場合は `kustomization.yaml` の resources から `service.yaml` を削除してください。

デフォルトではコンテナのポート `8080` が公開され、Service はポート `80` でアクセスを受け付けます。ポート番号を変更する場合は `deployment-patch.yaml` と `service.yaml` を編集してください（詳細は「ポート番号の変更」セクションを参照）。

#### 4. 実行

```bash
# dry-run で確認
kubectl apply -k overlays/my-deployment --dry-run=client -o yaml

# 実際にデプロイ
kubectl apply -k overlays/my-deployment
```

#### 5. 削除

```bash
kubectl delete -k overlays/my-deployment
```

---

## 設定項目

### 環境変数 (ConfigMap)

| 変数名 | 必須 | デフォルト | 説明 |
|--------|------|------------|------|
| `GIT_REPO_URL` | ✅ | - | GitリポジトリのURL |
| `GIT_BRANCH` | - | `main` | クローンするブランチ |
| `GIT_SUBDIR` | - | - | リポジトリ内のサブディレクトリ (スクリプトがサブディレクトリにある場合) |
| `SCRIPT_COMMAND` | ✅ | - | 実行するコマンド |

### Secret (Private リポジトリ用)

| キー名 | 説明 |
|--------|------|
| `GIT_TOKEN` | GitHub Personal Access Token (fine-grained推奨) |

## Private リポジトリの使用

### 1. GitHub Personal Access Token を作成

1. GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. "Generate new token" をクリック
3. "Repository access"で必要なリポジトリを選択．"Permissions"で`Contents`を選択し，`Read-only` 権限を付与
4. トークンを生成してコピー

### 2. Kubernetes Secret を作成

オーバーレイでSecretを定義:

```yaml
# overlays/my-job/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
type: Opaque
stringData:
  GIT_TOKEN: github_pat_xxxxx
```

### 3. kustomization.yaml でSecretを参照

該当箇所のコメントアウトを解除する．

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-namespace

resources:
  - ../../base/single-job
  - secret.yaml  # Secretリソースを追加

patches:
  - path: job-patch.yaml
```

---

## 依存関係の管理

スクリプトの依存関係は以下のいずれかで管理できます（優先順位順）:

### 1. pyproject.toml

```toml
[project]
name = "my-script"
version = "0.1.0"
dependencies = [
    "requests>=2.28.0",
    "pandas>=2.0.0",
]
```

### 2. requirements.txt

```
requests>=2.28.0
pandas>=2.0.0
```

entrypoint スクリプトは以下の順序でチェックします:
1. `pyproject.toml` があれば `pip install .`
2. なければ `requirements.txt` があれば `pip install -r requirements.txt`
3. どちらもなければ依存関係のインストールをスキップ

## サンプルスクリプト構成

```
your-scripts/
├── pyproject.toml      # または requirements.txt
├── main.py             # エントリーポイント
└── src/
    └── your_module/
        └── __init__.py
```

---

## トラブルシューティング

### Jobのログを確認

```bash
# Pod名を取得
kubectl get pods -l job-name=<job-name> -n <namespace>

# initContainer のログ (git clone)
kubectl logs <pod-name> -c git-clone -n <namespace>

# mainContainer のログ (スクリプト実行)
kubectl logs <pod-name> -c script-runner -n <namespace>
```

### よくある問題ほか

#### `fatal: could not read Username for 'https://github.com'`

Private リポジトリに対してトークンが設定されていません。上記の「Private リポジトリの使用」セクションを参照してください。

## カスタマイズ

### リソース制限の変更

- **Job**: `overlays/my-single-job/job-patch.yaml` を編集する．
- **CronJob**: `overlays/my-cronjob/cronjob-patch.yaml` を編集する．
- **Deployment**: `overlays/my-deployment/deployment-patch.yaml` を編集する．

### podにラベルを付与

`overlays/my-single-job/kustomization.yaml`、`overlays/my-cronjob/kustomization.yaml`、または`overlays/my-deployment/kustomization.yaml`内の「オプション podにラベルを追加する場合」の部分を編集してください．

### Deployment固有の設定

#### ポート番号の変更

デフォルトではコンテナポート `8080`、Service ポート `80` が設定されています。変更する場合は以下の2ファイルを編集してください。

`deployment-patch.yaml` でコンテナポートを変更:

```yaml
          ports:
            - $patch: replace
            - name: http
              containerPort: 3000  # アプリケーションのポートに合わせて変更
              protocol: TCP
```

`service.yaml` で Service ポートを変更:

```yaml
spec:
  ports:
    - name: http
      port: 3000       # 外部に公開するポート
      targetPort: http  # コンテナの named port に自動追従
      protocol: TCP
```

コンテナポートは `deployment-patch.yaml` 内の `$patch: replace` により base の定義が完全に置き換えられるため、意図しないポートが残ることはありません。Service はオーバーレイ側で直接定義しているため、そのまま編集するだけで変更できます。

#### MetalLB による外部IP割り当て

`kustomization.yaml` 内の MetalLB パッチのコメントアウトを解除し、アドレスプールやIPアドレスを設定してください。Service タイプが `LoadBalancer` に変更されます。

### CronJob固有の設定

| 設定項目 | デフォルト | 説明 |
|--------|------------|------|
| `schedule` | `"0 0 * * *"` | cron式でスケジュールを指定 |
| `concurrencyPolicy` | `Forbid` | 同時実行ポリシー (`Forbid` / `Allow` / `Replace`) |
| `successfulJobsHistoryLimit` | `3` | 成功したJobの履歴保持数 |
| `failedJobsHistoryLimit` | `3` | 失敗したJobの履歴保持数 |