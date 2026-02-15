# WBS（Google Spreadsheet）連携 要件定義（Notion + 中間DB + 配信）

## 1. 目的 / 背景
- PMが管理するWBS（Google Spreadsheet）を起点に、Notion（タスクDB）や他ツール（Jira/GitHub Projects等）へ連携し、二重入力と更新漏れを減らす。
- 変更差分を安全に取り込み、必要に応じて Notion 側の更新（担当/状態など）を Sheets に戻せるようにする。
- 中間データ（JSON/CSV相当の正規化データ）を PostgreSQL に蓄積し、履歴・監査・レポート作成を可能にする。

## 2. スコープ
### 2.1 対象（In scope）
- Google Spreadsheet 上のWBSを「行＝タスク」として扱い、Notion Database にタスクとして同期（Upsert）。
- 同期は差分ベース（hash/updated_at）を基本とし、全量同期（リビルド）も可能にする。
- Notion→Sheets の逆流は「限定フィールドのみ」「衝突回避ルールあり」を前提に実装可能とする。
- PostgreSQL に正規化データを保存し、スナップショット（週次など）と差分レポート生成の土台にする。
 - 段階導入:
   - Phase 1: Sheets → 中間生成ファイル（JSON/CSV）出力（まずここを実装する）
   - Phase 2: 中間データ → Notion 連携
   - Phase 3: 中間データ → GitHub Projects（等）連携

### 2.2 対象外（Out of scope）
- Notion上で完全なWBS編集体験を提供する（Notionを主データ化する）こと。
- ガント依存線、クリティカルパス自動算出などの高度なPM機能。
- 個別ツール（Jira/GitHub Projects）への配信をMVPで必須とすること（段階導入前提）。

## 3. 関係者 / 利用者
- PM: WBS作成・更新、進捗把握、レポート作成
- 開発メンバー: Notionでタスク閲覧・ステータス更新（必要なら）
- 管理者: n8n/DB/各種Credential管理、運用監視

## 4. 用語
- WBS行: Sheetsの1行（1タスク）を指す
- `wbs_id`: タスク行を一意に識別するID（手動/自動採番）
- Upsert: `wbs_id` をキーに Notion 側を「なければ作成、あれば更新」
- 差分同期: 前回同期から変わった行だけを処理

## 5. データ要件（最小）
### 5.1 Sheets（入力）想定カラム
必須:
- `wbs_id`（例: `WBS-000123`）
- `title`（タスク名）
推奨:
- `owner`（担当者: メール/表示名/Notionユーザー識別子のいずれか）
- `status`（未着手/進行中/レビュー/完了/保留 など）
- `start_date`, `end_date`
- `estimate_h`, `actual_h`
- `priority`（P0/P1/P2 等）
- `parent_wbs_id`（親タスクの `wbs_id`）
- `milestone`（任意）
- `url`（関連リンク）
同期制御:
- `updated_at`（手動更新でもよいが、可能なら自動）
- `row_hash`（同期用ハッシュ。n8nで計算して書き戻す運用でも可）
- `sync_status`（OK/NG、エラー要約）
- `notion_page_id`（Notion作成後に保存。Upsert高速化に使う）

### 5.2 Notion（出力）DBプロパティ
必須:
- `WBS ID`（text）
- `Name`（title）
推奨:
- `Status`（select）
- `Owner`（people）
- `Start`（date）
- `End`（date）
- `Estimate (h)`（number）
- `Actual (h)`（number）
- `Priority`（select）
- `Parent`（relation: 同DB）
- `Milestone`（select/text）
- `Source URL`（url）
同期制御:
- `Last Synced At`（date）
- `Source Updated At`（date: Sheets側更新日時）
- `Source Hash`（text）

### 5.3 PostgreSQL（中間）テーブル（案）
- `wbs_tasks_current`
  - `wbs_id`（PK相当）
  - 正規化カラム（title/status/owner/...）
  - `source`（例: `sheets`）
  - `source_updated_at`, `source_hash`
  - `notion_page_id`（任意）
  - `synced_at`
- `wbs_tasks_snapshots`
  - `snapshot_id`（週次など）
  - `captured_at`
  - `wbs_id` + 正規化カラム一式
- `wbs_sync_runs`
  - 実行単位のログ（開始/終了/件数/失敗件数/エラー）

## 6. 機能要件
### 6.1 Sheets → Notion（主フロー）
- SheetsからWBS行を取得する。
- 各行の `wbs_id` をキーに Notion DB を検索し、存在すれば更新、なければ作成する。
- 親子関係:
  - `parent_wbs_id` がある行は、対応する親ページとのRelationを設定する。
  - 親が未作成の場合は「親を先に作る」か「後で再試行」する（実装方針は後述）。
- 成功時:
  - NotionページID、同期時刻、hash等を Sheets および/または PostgreSQL に記録する。
- 失敗時:
  - 失敗した行を特定できる形でログ化し、`sync_status` 等へエラー要約を残す。

### 6.2 差分同期（基本）
- 同期対象の判定は以下のいずれか（MVPは1つに絞る）:
  - A) `updated_at` が前回同期時刻より新しい行のみ
  - B) `row_hash` が Notion/DB に保存した `source_hash` と異なる行のみ
- 判定材料が不足する場合は全量同期をフォールバックとして使える。

### 6.3 Notion → Sheets（逆流、任意）
- 逆流対象フィールドは限定する（例: `Owner`, `Status`, `Actual (h)` のみ）。
- 逆流のトリガーは以下のいずれか:
  - A) Notionの更新イベント（Webhook/ポーリング相当）
  - B) 定期実行で「Last edited time」を見て差分を拾う
- 衝突回避:
  - 「片方向（Sheetsが正）」または「フィールド単位の優先（例: StatusはNotion優先、日付はSheets優先）」を明文化する。
  - 同一フィールドが双方で更新されていた場合の扱い（保留/通知/優先）を定義する。

### 6.4 中間データ（正規化）と配信
- Sheets入力を正規化して PostgreSQL `wbs_tasks_current` に保存する（Notion同期前後どちらでも可）。
- 週次などで `wbs_tasks_snapshots` を作成し、差分（追加/変更/削除）を算出可能にする。
- 配信（将来）:
  - Jira/GitHub Projects へは `wbs_tasks_current` をソースとして連携する（分岐の影響を減らす）。

### 6.5 削除・完了・アーカイブ
- Sheets側で行削除は原則扱わず、`status=Archived` 等で表現（Notion側も同様）。
- ハード削除する場合は「同期対象外」「二重削除防止」など運用ルールを別途定義する。

## 7. 親子関係（順序制御）要件
- 最低要件: 親が未作成でも同期は止めず、Relation未設定としてリトライ対象にできること。
- 推奨: 同期1回の中で
  - 1パス目: 親子関係なしで全タスクUpsert（ページID確保）
  - 2パス目: `parent_wbs_id` を参照してRelationを設定

## 8. 非機能要件
- 安全性:
  - Credentialはn8nのCredential機構で管理し、リポジトリへ平文保存しない。
  - 実行ログに個人情報（メール等）を過度に出さない（マスキング方針）。
- 監査性:
  - `wbs_sync_runs` に実行履歴を残し、失敗行の特定が可能。
- 再実行性:
  - 同じデータで繰り返し実行しても「二重作成しない」（idempotent）。
- 性能:
  - 1回あたり数百〜数千行を想定。APIレート制限を考慮し、バッチ/スロットリングを入れる余地。
- 可観測性:
  - 失敗時はSlack/メールなどへ通知（MVPではログ+手動確認でも可）。

## 9. 受入条件（Acceptance Criteria）案
- SheetsのWBS行（`wbs_id` + `title`）が Notion DB に作成される。
- Sheets側で `status` を変更すると Notion 側が更新される（差分同期が効く）。
- 同期を2回連続で実行しても Notion に重複タスクが作成されない。
- `parent_wbs_id` を設定すると Notion のRelation（Parent）が設定される（少なくともリトライで最終的に一致する）。
- 失敗行が `wbs_id` 単位で追跡でき、再実行で復旧できる。
- （逆流を採用する場合）Notionで `Status` を更新すると Sheets に反映されるが、衝突時のルールどおりに動作する。

## 10. 未決事項（要確認）
- Sheetsの `wbs_id` 採番は誰がどう行うか（手動/自動/行番号ベース/UUID）。
- `updated_at` をどう運用するか（手入力/Apps Script/同期時にn8nが書き戻す）。
- Notion DB のプロパティ設計（peopleのマッピング方法: メール→Notionユーザーなど）。
- 衝突解決の基本方針（片方向か、フィールド単位の優先か）。
- 行の削除/アーカイブの運用（Sheets/Notion/DBの整合）。
- スナップショット頻度（毎日/週次/月次）とレポート出力先（Notionページ/Slack/スプレッドシート）。
