# dev-n8n

## Compose files
- `docker-compose.yml`: devcontainer 用（`apps` サービス）
- `src/docker-compose.yml`: n8n + PostgreSQL 用（n8n UI は `http://localhost:5678/`）

## Devcontainer での起動
- devcontainer では `docker-compose.yml`（apps）に加えて `src/docker-compose.yml`（n8n/postgres）も同時に起動する設定にしている。
- VS Code で Dev Containers を開いたら、n8n は `http://localhost:5678/` でアクセスできる（`forwardPorts` で 5678 を転送）。

## Codex (devcontainer)
- devcontainer イメージビルド時に Codex CLI（`codex`）をインストールする。
- Codex を使う場合は devcontainer 内で `OPENAI_API_KEY` を設定する（`export OPENAI_API_KEY=...`）。

## Phase 1 (WBS export): Google Spreadsheet -> intermediate JSON file
設計書:
- `docs/plan/wbs-intermediate-export.md`
- `docs/plan/wbs-intermediate-export-detail.md`

ワークフロー雛形:
- `src/n8n/workflows/sheets-to-intermediate-file.json`

### 起動（n8n + postgres）
```powershell
cd src
docker compose up -d
```

### 環境変数（例）
`src/.env.example` は参考として残していますが、ワークフロー雛形は `$env.*` を使わない構成にしてあります（n8n 側の設定によっては env 参照がブロックされるため）。

### 実行
1. n8n にログインして Google Sheets OAuth2 credential を作成（名前は任意）
2. `src/n8n/workflows/sheets-to-intermediate-file.json` を import
3. `Google Sheets (Read WBS)` ノードを開いて、作成した credential を選択
4. `Config` ノードの `wbs_sheet_id`（必須）、`wbs_sheet_name` / `wbs_sheet_range`（任意）を設定
5. Manual Trigger で実行
6. `src/data/exports/` に `wbs_*.json` が出力されることを確認

### Google OAuth2（self-host / Docker）注意点
- Google 側で有効化が必要: Google Sheets API / Google Drive API
- Redirect URI は n8n の credential 画面に出る `OAuth Redirect URL` を正として、Google Cloud Console の `Authorized redirect URIs` に完全一致で登録する
- リバプロ配下などで n8n の URL が `http://localhost:5678/` 以外になる場合は、`src/docker-compose.yml` の `WEBHOOK_URL`（必要に応じて `N8N_EDITOR_BASE_URL`）を実アクセスURLに合わせてから credential を作成する

### よくあるエラー
- `access to env vars denied`: 古い雛形が `$env.*` を参照している。最新の雛形を再importし、`Config` ノードを使う。
- `Can not get sheet 'undefined'`: `Config` の `wbs_sheet_id` / `wbs_sheet_name` が未設定、または `Manual Trigger -> Config -> Google Sheets` の接続になっていない。
- `Node does not have any credentials set`: `Google Sheets (Read WBS)` ノードで credential を選択して保存する。


https://docs.n8n.io/integrations/builtin/credentials/google/oauth-single-service/