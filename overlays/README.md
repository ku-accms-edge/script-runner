# overlays/

あなた自身のオーバーレイ (環境固有の設定) を置くディレクトリです。

`examples/` からコピーして作成するか、対話的セットアップを使ってください:

```bash
# 手動でコピーする場合
cp -r examples/single-job overlays/my-single-job

# 対話的に作成する場合
./setup.sh
```

このディレクトリの中身は git で管理されるため、fork したリポジトリで
自分のマニフェストの差分管理ができます。

> **Note:** `secret.yaml` (トークン等の機密情報) は `.gitignore` により
> 常にコミット対象から除外されます。
