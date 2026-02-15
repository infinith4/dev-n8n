# Phase 1 要件定義: Google Spreadsheet → 中間生成ファイル（JSON/CSV）出力

## 1. 目的 / 背景
- PMが管理するWBS（Google Spreadsheet）を、後続連携（Notion/GitHub Projects等）の前段として“中間データ”に落とす。
- Phase 1では「取得→正規化→ファイル出力」までを確実に作り、以降の連携先追加はこの中間データを入力として実装する。

## 2. スコープ
### 2.1 対象（In scope）
- Google Sheets からWBSを読み取り、行データを正規化して JSON/CSV ファイルとして出力する。
- 出力はローカルの `src/data/exports/`（n8nコンテナ内 `/exports`）に保存する。
- 出力ごとにメタ情報（生成時刻、ソース情報、件数など）を付与する。

### 2.2 対象外（Out of scope）
- Notion/GitHub Projects 等への同期（Phase 2以降）。
- 差分検知や双方向更新（Phase 1では“全量エクスポート”を基本）。

## 3. 前提 / 制約
- 認証方式: n8nの Google Sheets ノード（OAuth2 credential）でアクセスする。
- Sheets側の列は「ヘッダー行が存在」し、ヘッダー名でマッピングできることを前提とする。
- 出力ファイルは成果物ではなく中間生成物なので、リポジトリにはコミットしない（`.gitkeep`のみ保持）。
 - n8n の設定によってはノード内からの環境変数参照（`$env.*`）が禁止されるため、ワークフロー雛形は `$env.*` を使用しない（後述の `Config` ノードで指定する）。

## 3.1 Google OAuth2（self-host / Docker）設定メモ
前提: n8n は `http://localhost:5678/` でアクセスできる（`src/docker-compose.yml`）。

1. Google Cloud Console でプロジェクト作成
2. API を有効化: Google Sheets API / Google Drive API
3. OAuth 同意画面を設定
4. OAuth クライアントを作成（Web application）
5. n8n の Credentials 画面で Google OAuth2（Single service: Google Sheets）credential を作り、表示される `OAuth Redirect URL` をコピー
6. Google 側の OAuth クライアントに `Authorized redirect URIs` として 5 の URL を完全一致で登録（末尾スラッシュ含め一致必須）
7. n8n の credential に Client ID / Client Secret を設定して Connect

補足:
- リバースプロキシ配下や別ドメインで使う場合、n8n が「自分のURL」をどう認識しているかが Redirect URL に反映される。`WEBHOOK_URL`（必要に応じて `N8N_EDITOR_BASE_URL`）を実アクセスURLに合わせてから credential を作成する。

## 4. 入力データ要件（Sheets）
必須:
- `wbs_id`（一意キー）
- `title`
任意（あれば出力に含める）:
- `owner`, `status`, `start_date`, `end_date`, `estimate_h`, `actual_h`, `priority`, `parent_wbs_id`, `milestone`, `url`, `updated_at`

## 5. 出力要件
### 5.1 出力先
- ホスト: `src/data/exports/`
- コンテナ: `/exports`（`src/docker-compose.yml` で bind mount）

### 5.2 ファイル命名
- JSON: `wbs_YYYYMMDD_HHMMSS.json`
- CSV: `wbs_YYYYMMDD_HHMMSS.csv`（Phase 1ではJSON優先。CSVは後続で追加可）

### 5.3 JSONフォーマット
補足: 実装では `generated_at` は `Date#toISOString()`（UTC, `...Z`）で出力する。
```json
{
  "generated_at": "2026-02-15T06:00:00.000Z",
  "source": {
    "type": "google_sheets",
    "spreadsheet_id": "xxxxxxxxxxxxxxxxxxxx",
    "sheet_name": "WBS",
    "range": "A:Z"
  },
  "count": 1,
  "error_count": 0,
  "tasks": [
    {
      "wbs_id": "WBS-000123",
      "title": "ログイン画面",
      "owner": "taro@example.com",
      "status": "In Progress",
      "start_date": "2026-02-10",
      "end_date": "2026-02-20",
      "estimate_h": 16,
      "actual_h": 8,
      "priority": "P1",
      "parent_wbs_id": "WBS-000100",
      "milestone": "M1",
      "url": "https://example.com/spec",
      "source_updated_at": "2026-02-15T14:59:00+09:00",
      "row_hash": "sha256:...."
    }
  ],
  "errors": []
}
```

### 5.4 正規化ルール（最低限）
- 数値: `estimate_h`, `actual_h` は数値に変換できる場合のみ数値で出力し、無理なら `null`
- `row_hash`: 正規化後のタスクJSON（`row_hash`自身を除く）を `sha256` し、`sha256:<hex>` として出力
- 日付/日時: Phase 1では入力値をそのまま出力し、厳密なバリデーションはPhase 2で強化（ただし破損データはログで検知できること）

## 6. 機能要件（n8n）
### 6.1 実行トリガー
- 手動実行（Manual Trigger）でよい（定期実行は後で追加可能）。

### 6.2 取得範囲の設定
- ワークフロー内の `Config` ノードで指定できること:
  - `wbs_sheet_id`（必須）
  - `wbs_sheet_name`（任意、デフォルト `WBS`）
  - `wbs_sheet_range`（任意、デフォルト `A:Z`）

### 6.3 エラー処理 / ログ
- Sheets取得に失敗した場合、ワークフローは失敗として終了し、原因が追えるログが残ること。
- 変換に失敗した行がある場合も、可能なら他行は出力しつつ、問題行が特定できるようにする（Phase 1では“全体失敗”でも可だが、方針を明文化する）。

## 7. 非機能要件
- 再現性: 同じ入力で実行したとき、タスク配列の内容（hash含む）が安定する（順序・正規化の揺れを極力なくす）。
- 可搬性: 出力JSONは後続（Notion/GitHub Projects）でそのまま入力に使えること。
- セキュリティ: CredentialやSheet IDなど機密をリポジトリへ平文で固定しない（n8n Credential ストアで管理し、ワークフロー側の `Config` は実運用では外部化することを推奨）。

## 8. 受入条件（Acceptance Criteria）
- 指定したスプレッドシートから行を取得し、`src/data/exports/` に `wbs_*.json` が生成される。
- 生成ファイルに `generated_at/source/count/tasks` が含まれる。
- 各タスクに `row_hash` が付与される。

## 9. 実装物（現状）
- 出力ディレクトリ: `src/data/exports/`（`.gitkeep`）
- n8nワークフロー雛形: `src/n8n/workflows/sheets-to-intermediate-file.json`

## 10. 未決事項
- Sheetsのヘッダー名（実際の列名）をどれに揃えるか（`wbs_id/title/owner/...`）
- CSVも同時に出すか、Phase 2で追加するか

---

# Phase 1 基本設計: Sheets → 中間生成ファイル出力

## 11. 全体構成（コンポーネント）
- Google Spreadsheet（WBS）
- n8n（取得/正規化/ファイル出力）
- 出力ディレクトリ（ホスト）: `src/data/exports/`
- 出力ディレクトリ（コンテナ）: `/exports`（`src/docker-compose.yml` の bind mount）

## 12. データフロー（シーケンス）
1. n8nワークフローを手動実行（Manual Trigger）
2. Google Sheets API で対象範囲を取得（ヘッダー行をキーとして行JSONを生成）
3. 行ごとに正規化（型変換、キー整形、`row_hash` 付与）
4. エクスポート用のラッパJSON（`generated_at/source/count/tasks`）を組み立て
5. `/exports/wbs_YYYYMMDD_HHMMSS.json` に書き込み

## 13. 設定（環境変数）
雛形ワークフローは `$env.*` を使わないため、`Config` ノードで指定する。
- `wbs_sheet_id`（必須）: 対象スプレッドシートID
- `wbs_sheet_name`（任意）: 対象シート名（デフォルト `WBS`）
- `wbs_sheet_range`（任意）: 取得範囲（デフォルト `A:Z`）

補足:
- Google Sheets の認証は n8n Credential（OAuth2）で行う（リポジトリには保持しない）。

## 14. 正規化設計（データマッピング）
### 14.1 入力行 → 正規化タスク
- 入力は「ヘッダー名 → 値」の辞書として受け取る前提
- 正規化後のキー（Phase 1の中間フォーマット）:
  - `wbs_id`, `title`, `owner`, `status`, `start_date`, `end_date`
  - `estimate_h`, `actual_h`, `priority`
  - `parent_wbs_id`, `milestone`, `url`
  - `source_updated_at`
  - `row_hash`

### 14.2 型変換ルール
- `estimate_h`, `actual_h`: `Number()` で変換できる場合のみ数値、それ以外は `null`
- `row_hash`: `row_hash` を除いた正規化タスクを `JSON.stringify` → `sha256` → `sha256:<hex>`
- 日付/日時: Phase 1では「入力値をそのまま」出力（バリデーションはPhase 2で強化）

### 14.3 ヘッダー揺れの吸収
`src/n8n/workflows/sheets-to-intermediate-file.json` の正規化処理では以下のような別名も吸収する。
- `wbs_id`: `WBS_ID`, `WBS ID`, `id`
- `title`: `Title`, `name`, `Name`
- それ以外も `Owner/Status/Start/End/...` を候補として拾う

## 15. n8nワークフロー設計
ファイル: `src/n8n/workflows/sheets-to-intermediate-file.json`

### 15.1 ノード構成
- `Manual Trigger`
- `Config`:
  - `wbs_sheet_id`, `wbs_sheet_name`, `wbs_sheet_range` を定義
- `Google Sheets (Read WBS)`:
  - `documentId`: `{{$json.wbs_sheet_id}}`
  - `sheetName`: `{{$json.wbs_sheet_name || 'WBS'}}`
  - `range`: `{{$json.wbs_sheet_range || 'A:Z'}}`
- `Normalize WBS Rows`（Function）:
  - 入力行→正規化タスク
  - `row_hash` を計算して付与
- `Build Export JSON`（Function）:
  - `fileName`（時刻ベース）と `content`（ラッパJSON）を生成
- `JSON to Binary`:
  - JSONを書き込み可能なバイナリに変換（ファイル名付与）
- `Write Export File`:
  - `=/exports/{{$binary.data.fileName}}` に書き込み

### 15.2 出力JSONの確定
- `generated_at`: ISO8601（`Date#toISOString()`）
- `source`: `type/spreadsheet_id/sheet_name/range`
- `count`: `tasks.length`
- `tasks`: 正規化タスク配列

## 16. エラーハンドリング設計（Phase 1）
### 16.1 失敗の扱い（基本）
- Sheets取得失敗: ワークフローは失敗終了（出力なし）
- 正規化失敗:
  - 現状の雛形は「全行を処理」する前提なので、例外が出た場合は失敗終了
  - 次の改善候補（Phase 1.1）: 行単位で例外を握りつぶして `errors[]` を別途出力/通知

### 16.2 必須項目欠落の扱い
- `wbs_id` または `title` が欠落している行は、Phase 1では出力対象から除外する運用が安全
  - 現状の雛形は除外/エラーのどちらにも寄せられるため、運用方針を決めて実装に反映する

## 17. 運用/確認手順（最小）
1. n8nで Google Sheets Credential（OAuth2）を作成（名前は任意）
2. ワークフローを import
3. `Google Sheets (Read WBS)` ノードで credential を選択
4. `Config` ノードで `wbs_sheet_id` を設定（必要に応じて `wbs_sheet_name` / `wbs_sheet_range` も設定）
5. Manual Trigger で実行
6. `src/data/exports/` に `wbs_*.json` が作成されることを確認

## 18. 詳細設計
- 詳細設計書: `docs/plan/wbs-intermediate-export-detail.md`
