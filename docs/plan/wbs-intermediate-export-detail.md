# Phase 1 詳細設計書: Google Spreadsheet → 中間生成ファイル（JSON）出力

対象: Phase 1（Sheets→中間ファイル出力）。Notion/GitHub Projects 連携は対象外。

## 1. 設計方針
- 後続連携（Notion/GitHub Projects等）が参照できる「安定した中間JSON」を作る。
- Phase 1は全量エクスポートを基本とし、差分同期/双方向更新はPhase 2以降で扱う。
- 入力の揺れ（ヘッダー名、空欄、型の違い）を吸収しつつ、最低限の品質（必須項目、hash）を担保する。

## 2. 成果物（実装物）
- n8nワークフロー雛形: `src/n8n/workflows/sheets-to-intermediate-file.json`
- 出力ディレクトリ（ホスト）: `src/data/exports/`
- n8nコンテナ内マウント: `/exports`（`src/docker-compose.yml`）

## 3. 外部I/F
### 3.1 入力（Google Sheets）
- 認証: n8n Credential（Google Sheets OAuth2）
- 対象指定（ワークフロー内 `Config` ノード）:
  - `wbs_sheet_id`（必須）
  - `wbs_sheet_name`（任意、デフォルト `WBS`）
  - `wbs_sheet_range`（任意、デフォルト `A:Z`）

### 3.2 出力（JSONファイル）
- 出力先: `/exports`（ホスト `src/data/exports/`）
- 命名: `wbs_YYYYMMDD_HHMMSS.json`
- 文字コード: UTF-8

## 4. データ仕様（確定）
### 4.1 出力JSONスキーマ（概略）
トップレベル:
- `generated_at` string（ISO8601, UTC: `toISOString()`）
- `source` object
  - `type` = `google_sheets`
  - `spreadsheet_id` string|null
  - `sheet_name` string
  - `range` string
- `count` number（出力タスク数）
- `error_count` number（スキップ行数）
- `tasks` array of Task
- `errors` array of Error（スキップ行の要約）

Task:
- `wbs_id` string（必須）
- `title` string（必須）
- `owner` string|null
- `status` string|null
- `start_date` string|null
- `end_date` string|null
- `estimate_h` number|null
- `actual_h` number|null
- `priority` string|null
- `parent_wbs_id` string|null
- `milestone` string|null
- `url` string|null
- `source_updated_at` string|null
- `row_hash` string（`sha256:<hex>`）

Error:
- `reason` string（例: `missing_wbs_id_or_title`）
- `raw` object（入力行の一部。個人情報が含まれる場合はマスク検討）

### 4.2 必須判定
- `wbs_id` または `title` が空（null/undefined/空文字/空白のみ）の行は `tasks` に含めない。
- その代わり `errors[]` に集計して出力する（Phase 1での運用可視化のため）。

### 4.3 型変換
- 数値:
  - `estimate_h` / `actual_h` は `Number(trimmed)` が有限数なら number、そうでなければ `null`
- 文字列:
  - 文字列は `String(v)` で取り扱うが、空白のみは `null` 扱いを推奨（ただしPhase 1は厳格化しすぎない）
- 日付:
  - Phase 1は入力値をそのまま格納（`YYYY-MM-DD` を推奨）

### 4.4 `row_hash` 計算
- 対象: 正規化タスク（`row_hash` 自身を除いたJSON）
- 手順:
  1. 正規化タスク（`row_hash`なし）を `JSON.stringify`（キー順はオブジェクト生成順で固定）
  2. `sha256` を計算して hex化
  3. `sha256:<hex>` を `row_hash` として付与

## 5. n8n ワークフロー詳細
### 5.1 ノード一覧
1. `Manual Trigger`
2. `Config`（Set）
3. `Google Sheets (Read WBS)`（read）
4. `Normalize WBS Rows`（Function）
5. `Build Export JSON`（Function）
6. `JSON to Binary`（Move Binary Data: jsonToBinary）
7. `Write Export File`（Write Binary File）

### 5.2 ノード別詳細
#### 5.2.1 Config（Set）
- 目的: `$env.*` を使わずに対象スプレッドシート/範囲を指定する（n8n の設定によってはノード内 env 参照がブロックされるため）。
- 設定値:
  - `wbs_sheet_id`（必須）
  - `wbs_sheet_name`（任意、デフォルト `WBS`）
  - `wbs_sheet_range`（任意、デフォルト `A:Z`）

#### 5.2.2 Google Sheets (Read WBS)
- `documentId`: `={{$json.wbs_sheet_id}}`
- `sheetName`: `={{$json.wbs_sheet_name || 'WBS'}}`
- `range`: `={{$json.wbs_sheet_range || 'A:Z'}}`
- 前提: 1行目がヘッダーで、n8n側が「ヘッダー→値」のJSON行を返す
- 事前設定: ノードの `Credentials` に Google OAuth2 credential を設定する（未設定だと `Node does not have any credentials set`）

#### 5.2.3 Normalize WBS Rows（Function）
責務:
- ヘッダー揺れを吸収し、Taskへ正規化
- 必須欠落を検知してスキップ用レコード（Error）へ変換
- Taskに `row_hash` を付与

入力:
- `items[]`: Sheets行（`item.json` が行データ）

出力:
- `items[]`: 1行→1レコード
  - Taskレコード: `{"_skip": false, ...Task}`
  - Errorレコード: `{"_skip": true, "reason": "...", "raw": {...}}`

#### 5.2.4 Build Export JSON（Function）
責務:
- `_skip` を見て `tasks[]` と `errors[]` を分離
- ファイル名（時刻ベース）と出力JSON（ラッパ）を組み立て

出力:
- `fileName`: `wbs_YYYYMMDD_HHMMSS.json`
- `content`: 上記スキーマ準拠

#### 5.2.5 JSON to Binary / Write Export File
- `Write Export File.filePath`: `=/exports/{{$binary.data.fileName}}`
- 出力確認はホスト側 `src/data/exports/` を参照

## 6. 例外・障害設計
### 6.1 失敗時の挙動
- Sheets取得失敗: ワークフロー失敗（ファイル出力なし）
- 正規化処理の例外: ワークフロー失敗（ファイル出力なし）

### 6.2 スキップ行の扱い
- 必須欠落行は処理継続し、`errors[]` に集計する（エクスポート自体は成功扱い）。

## 7. セキュリティ/設定管理
- Google OAuth2 credential は n8n の Credential ストアで管理し、リポジトリには保存しない。
- Sheet ID 等はワークフローの `Config` ノードに設定する（実運用では外部化することを推奨。リポジトリに固定値をコミットしない）。
- self-host（Docker）の Google OAuth2 は Redirect URI の完全一致が必須。n8n の credential 画面に表示される `OAuth Redirect URL` を Google 側の `Authorized redirect URIs` に登録する。

## 8. テスト観点（手動）
- 正常:
  - `wbs_id/title` が全行にある → `error_count=0`、`count=行数`
  - `estimate_h/actual_h` が数値文字列 → number で出力される
- 異常/揺れ:
  - `wbs_id` 空行 → `errors[]` に入り、`tasks` に入らない
  - ヘッダーが `WBS ID` / `Name` のように揺れる → 正規化される
- 再実行:
  - 同じ入力 → 同じ行の `row_hash` が変わらない（順序・整形が安定）
