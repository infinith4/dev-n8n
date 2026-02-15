# dev-n8n: テスト仕様書作成支援環境

n8nを使ってテスト仕様書の作成を自動化・効率化するための開発環境です。

## 必要なもの

- Docker & Docker Compose
- Node.js 22+ (ローカル開発用)

## クイックスタート

### 1. n8nを起動

```bash
./scripts/start-n8n.sh
```

または直接:

```bash
docker compose up -d n8n
```

### 2. ブラウザでアクセス

http://localhost:5678 を開き、初回はアカウントを作成します。

### 3. ワークフローをインポート

n8n UIで「Menu > Import from File」から以下のワークフローを読み込みます:

| ワークフロー | 説明 |
|---|---|
| `n8n/workflows/test-spec-generator.json` | Webhook APIでテスト仕様書を生成 |
| `n8n/workflows/test-spec-from-csv.json` | CSVデータからテスト仕様書を一括生成 |
| `n8n/workflows/test-spec-batch-from-spreadsheet.json` | 手動トリガーでバッチ生成 |

### 4. テスト仕様書を生成

ワークフローをインポートしてActivateした後、Webhook経由でテスト仕様書を生成できます:

```bash
# サンプルデータでテスト
./scripts/test-webhook.sh

# JSONで直接リクエスト
curl -X POST http://localhost:5678/webhook/generate-test-spec \
  -H "Content-Type: application/json" \
  -d @n8n/templates/sample-request.json
```

## ワークフロー詳細

### 1. テスト仕様書生成 (Webhook API)

**Endpoint:** `POST /webhook/generate-test-spec`

JSON形式でテスト対象の情報を送信すると、Markdown形式のテスト仕様書を生成します。

```json
{
  "feature_name": "ユーザーログイン",
  "description": "メールアドレスとパスワードによるログイン機能",
  "author": "テスト太郎",
  "priority": "High",
  "category": "Authentication",
  "test_cases": [
    {
      "name": "正常ログイン",
      "precondition": "登録済みユーザーが存在する",
      "steps": "1. メールアドレスを入力 2. パスワードを入力 3. ログインボタンをクリック",
      "expected": "ダッシュボードに遷移する",
      "priority": "High"
    }
  ]
}
```

### 2. CSVからテスト仕様書一括生成

**Endpoint:** `POST /webhook/generate-test-spec-from-csv`

CSVデータを送信して一括でテスト仕様書を生成します。CSVの列は `name,precondition,steps,expected,priority` です。

### 3. 手動トリガー: バッチ生成

n8n UIから手動実行し、コード内に定義した機能一覧からテスト仕様書を一括生成します。テスト対象を編集して使用してください。

## ディレクトリ構成

```
dev-n8n/
├── docker-compose.yml          # n8n + 開発コンテナ定義
├── scripts/
│   ├── start-n8n.sh            # n8n起動スクリプト
│   └── test-webhook.sh         # Webhookテストスクリプト
├── n8n/
│   ├── workflows/              # n8nワークフローJSON
│   │   ├── test-spec-generator.json
│   │   ├── test-spec-from-csv.json
│   │   └── test-spec-batch-from-spreadsheet.json
│   ├── templates/              # テンプレートとサンプルデータ
│   │   ├── test-spec-template.md
│   │   ├── sample-request.json
│   │   └── sample-csv-request.json
│   └── output/                 # 生成されたテスト仕様書
└── src/                        # アプリケーションソースコード
    ├── index.ts
    ├── package.json
    └── tsconfig.json
```

## 停止

```bash
docker compose down
```
