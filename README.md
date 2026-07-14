# Git Script Runner for Kubernetes

Gitリポジトリから直接Pythonスクリプトを実行するためのKubernetesマニフェスト集です。

コンテナイメージをビルドすることなく、環境変数でGitリポジトリのURLと実行コマンドを指定するだけで、任意のPythonスクリプトをKubernetes Job、CronJob、または Deployment + Service として実行できます。

## 特徴

- **ビルド不要**: 公式のPythonイメージとalpine/gitイメージを使用
- **柔軟な設定**: Kustomizeで環境ごとの設定を簡単に管理
- **Job / CronJob / Deployment 対応**: 一度きりの実行、定期実行、常駐サービスに対応
- **Private リポジトリ対応**: GitHub Personal Access Token による認証をサポート
- **柔軟なビルドステップ**: `BUILD_COMMAND` で任意のコマンドを指定可能 (`pip install .` / `uv sync` など)。未指定時は `pyproject.toml` / `requirements.txt` を自動検出
- **カスタムコンテナ対応**: Git cloneなし・pipなしのイメージでも動作可能

## ディレクトリ構成

```
.
├── base/        # 共通マニフェスト (通常は編集不要)
├── examples/    # サンプルオーバーレイ (コピーして使う)
├── overlays/    # あなたのオーバーレイを置く場所
├── setup.sh     # 対話的セットアップヘルパー
└── del-and-run-single-job.sh
```

`overlays/` 以下は git の管理対象です (機密情報を含む `secret.yaml` は除く)。リポジトリをforkして使えば、自分で作成したマニフェストの差分管理ができます。

---

## クイックスタート

> **Tip:** `./setup.sh` を実行すると、以下の手順を対話形式で行い、必要なファイルを自動生成できます。
  実行する場合は、実行前に `chmod +x ./setup.sh` で実行権限を付与してください。

### Job (一度きりの実行) の場合
#### 1. リポジトリをクローン

```bash
git clone https://github.com/XXX/git-script-runner.git
cd git-script-runner
```

#### 2. オーバーレイを作成

```bash
cp -r examples/single-job overlays/my-single-job
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
cp -r examples/cronjob overlays/my-cronjob
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
cp -r examples/deployment overlays/my-deployment
```

#### 3. 設定をカスタマイズ

`overlays/my-deployment/kustomization.yaml` を編集:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-namespace  # 実行するnamespace

resources:
  - ../../base/deployment
  - service.yaml  # Service が必要な場合はこの行を追加

namePrefix: my-app-  # リソース名のプレフィックス

configMapGenerator:
  - name: script-runner-config
    behavior: replace
    literals:
      - GIT_REPO_URL=https://github.com/your-org/your-scripts.git
      - GIT_BRANCH=main
      - SCRIPT_COMMAND=python -m uvicorn main:app --host 0.0.0.0 --port 3000
```

Service はオプションです。必要な場合は `kustomization.yaml` の resources から `service.yaml` を追加してください。

ポート番号を変更する場合は `deployment-patch.yaml` と `service.yaml` を編集してください（詳細は「ポート番号の変更」セクションを参照）。

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
| `GIT_REPO_URL` | - | - | GitリポジトリのURL (未指定の場合、git cloneをスキップ) |
| `GIT_BRANCH` | - | `main` | クローンするブランチ |
| `GIT_SUBDIR` | - | - | リポジトリ内のサブディレクトリ (スクリプトがサブディレクトリにある場合) |
| `BUILD_COMMAND` | - | - | `SCRIPT_COMMAND` の前に実行するビルドコマンド。未指定時は自動検出、`skip` でスキップ (詳細は「ビルドステップ」セクション) |
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

## ビルドステップ (依存関係のインストール)

`SCRIPT_COMMAND` の実行前に、依存関係のインストール等を行うビルドステップが実行されます。動作は `BUILD_COMMAND` で制御します。

### BUILD_COMMAND を指定する場合

任意のコマンドを指定できます。Pythonに限らず、どんな言語・ツールでも使えます。

```yaml
configMapGenerator:
  - name: script-runner-config
    behavior: replace
    literals:
      # 例: pipでプロジェクトをインストール
      - BUILD_COMMAND=pip install .

      # 例: uvを使う (uvが入ったイメージへの変更が必要)
      # - BUILD_COMMAND=uv sync

      # 例: ビルドステップを完全にスキップ
      # - BUILD_COMMAND=skip
```

> **Note:** `uv` や `npm` など、デフォルトイメージ (`python:3.14-slim`) に含まれないツールを使う場合は、`job-patch.yaml` 等でコンテナイメージを変更してください。

### BUILD_COMMAND を指定しない場合 (自動検出)

Pythonプロジェクトとして以下の順序で自動検出します:

1. `pip` コマンドが存在しない場合、依存関係のインストールをスキップ
2. `pyproject.toml` があれば `pip install .`
3. なければ `requirements.txt` があれば `pip install -r requirements.txt`
4. どちらもなければ依存関係のインストールをスキップ

```toml
# pyproject.toml の例
[project]
name = "my-script"
version = "0.1.0"
dependencies = [
    "requests>=2.28.0",
    "pandas>=2.0.0",
]
```

```
# requirements.txt の例
requests>=2.28.0
pandas>=2.0.0
```

> **Note:** リポジトリに `pyproject.toml` があると自動的に `pip install .` が実行されるため、プロジェクトとしてインストール可能な状態になっている必要があります。意図しないインストールを避けたい場合は `BUILD_COMMAND` を明示的に指定するか、`BUILD_COMMAND=skip` を設定してください。
>
> **Note:** runnerコンテナのイメージをカスタムする場合、`pip` コマンドが存在しないイメージでも正常に動作します。

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

### CronJob固有の設定

| 設定項目 | デフォルト | 説明 |
|--------|------------|------|
| `schedule` | `"0 0 * * *"` | cron式でスケジュールを指定 |
| `concurrencyPolicy` | `Forbid` | 同時実行ポリシー (`Forbid` / `Allow` / `Replace`) |
| `successfulJobsHistoryLimit` | `3` | 成功したJobの履歴保持数 |
| `failedJobsHistoryLimit` | `3` | 失敗したJobの履歴保持数 |

### Deployment固有の設定

#### ポート番号の変更

変更する場合は以下の2ファイルを編集してください。

`deployment-patch.yaml` でコンテナポートを変更:

```yaml
          ports:
            - name: http
              containerPort: 3000  # アプリケーションのポートに合わせて変更
              protocol: TCP
```

`service.yaml` で Service ポートを変更:

```yaml
spec:
  ports:
    - name: http
      port: 80          # 外部に公開するポート
      targetPort: 3000  # deployment-patch.yaml の containerPort と合わせる
      protocol: TCP
```


<!-- #### MetalLB による外部IP割り当て

`kustomization.yaml` 内の MetalLB パッチのコメントアウトを解除し、アドレスプールやIPアドレスを設定してください。Service タイプが `LoadBalancer` に変更されます。 -->
