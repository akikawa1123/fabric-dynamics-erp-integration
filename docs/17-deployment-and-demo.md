# デプロイ状態・デモ手順・teardown（Task 012）

実装した Hosted Agent の稼働状態、デモの実行方法、コスト停止手順をまとめる。
更新: 2026-06-26。

## デプロイ済みリソース（`rg-seall-hackthon2026`）

| リソース | 値 |
|---|---|
| Foundry account / project | `ai-seall-hackthon2026-eastus2-001` / `pj-seall-hackthon`（eastus2） |
| **Hosted Agent** | `manufacturing-quality-agent`（**v4 / active / hosted**、Responses Protocol、`remote_build`） |
| モデル | `gpt-5.4`（+ `text-embedding-3-small`） |
| Fabric Data Agent 接続 | `da_manufacturing_erp`（Microsoft Fabric 型・OBO） |
| Foundry IQ | AI Search `srch-seall-hackthon2026-eastus-001`（Basic / **East US**）/ index `mq-quality-index`（5文書）/ KB `mq-quality-kb` |
| Toolbox | `mq-quality-toolbox`（`knowledge_base_retrieve` のみ、agentic-identity） |
| Fabric 容量 | `seallfabric`（F2 / westus3 / **Active**） |

## デモ経路

### 1. 営業（live・推奨）
デプロイ済みエージェントへ「Contoso の進行中受注を一覧で」→ Fabric Data Agent 経由で実 ERP データ（25件・候補）を出典付きで返す。Foundry ポータルの Agents Playground、または Responses API で実行。

### 2. Foundry IQ グラウンディング（live）
「圧入工程でトルクが規格上限を超えた場合の初動と過去の8Dを教えて」→ `knowledge_base_retrieve` が `8D-2025-014` / `CP-ST07-PRESS` / `PFMEA-PRESS-001` / `INSP-TORQUE-CAL-001` を出典付きで返す（検証済み）。

### 3. 工場（live・復旧済み）
工場ラインの品質テレメトリ（Lakehouse `lh_quality_analytics` `dbo.Telemetry`）に基づく。
デプロイ済みエージェントへ「今、品質異常は出ていますか？製品・ロット・ステーションと、トルクが規格上限(50Nm)を超えた直近イベントを」→ Fabric Data Agent 経由で実テレメトリ（異常ロット `LOT-CRCA-…-007` / `ST-07-PRESS` / トルク>50Nm）を**出典付き**で返す。**エージェント実装をローカル起動し、デプロイ済みの Foundry プロジェクト + Fabric Data Agent + Lakehouse に対して end-to-end 検証済み（約51秒。候補/未検証/担当役割の分離、自動実行なしを保持）**。

通常の取り込み経路（`telemetry_sender.py` → Eventstream → Lakehouse）が容量一時停止などで停止している場合は、フォールバックの直接シードで復旧する:
```powershell
uv run --no-project --with deltalake --with pyarrow --with azure-identity `
  python scenario-c/seed_lakehouse_telemetry_direct.py `
  --workspace-id <WS_GUID> --lakehouse-id <LH_GUID>
```
（Eventstream 着地スキーマ＝基本12列＋`EventEnqueuedUtcTime`(datetime2) を再現。Data Agent の時間フィルタに必須。既定は `--mode overwrite` で既存 Telemetry を置換するため、Eventstream 再開の前後は Fabric 担当と調整すること。）

fixture でもデモ可能:
```powershell
cd agent
uv run mq-agent-fixture factory ..\contracts\samples\investigation-request.json
uv run mq-agent-fixture factory ..\contracts\samples\investigation-request.json --tool-failure  # ツール失敗時=捏造なし
```

## 工場 live の状態（復旧済み・2026-06-26）
- Lakehouse `lh_quality_analytics` `dbo.Telemetry` を復旧し、**factory live を end-to-end 検証済み**（製品 `CRCA` / ロット `LOT-CRCA-…-007` / `ST-07-PRESS` / トルク>50Nm、出典付き、約51秒）。
- 復旧手段: 通常経路（`telemetry_sender.py` → Eventstream `es_client_telemetry` → Lakehouse）が容量一時停止で Eventstream ノード Inactive 化（公開 REST で再開不可）のため、`scenario-c/seed_lakehouse_telemetry_direct.py` で OneLake へ直接 Delta 書き込み（Eventstream バイパスのフォールバック）。Eventstream 着地スキーマ（基本12列＋`EventEnqueuedUtcTime` datetime2）を再現し、異常は `station_id + product_number + lot_id`（固定ロット）で識別できるよう集約。
- **注意（デモ運用）**: Fabric 容量 `seallfabric` を **Active** に保つ（Paused だと Data Agent が照会不可。シード済みデータ自体は容量状態に関わらず OneLake に永続）。
- ローカルで Fabric パスを単独検証する場合、Foundry IQ Toolbox は agentic-identity（AgentInstance/Blueprint）のためデプロイ時のみ解決可 → ローカルでは無効化して実行（Toolbox 取得はデプロイ済みエージェントで検証済み）。
- 既知の ERP データ品質3件（受注ID人名連結 / 数量が日付シリアル / 出荷日空欄）は Dataverse 由来の表示上の癖。candidate 判定・ルーティングには影響しない。

## コストと teardown（重要）
稼働中の主なコスト: **AI Search Basic ≈ $74/mo**、**Fabric 容量 F2（Active 時）**、Foundry のモデル従量。

デモしない間のコスト停止:
```powershell
$sub="00000000-0000-0000-0000-000000000000"; $rg="rg-seall-hackthon2026"
# Fabric 容量を一時停止（再開すれば live 再開可）
az rest --method post --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Fabric/capacities/seallfabric/suspend?api-version=2023-11-01"
```
完全撤去（コスト停止）:
```powershell
# AI Search 削除（KB/index/toolbox/connection も停止）
az search service delete -n srch-seall-hackthon2026-eastus-001 -g $rg --subscription $sub --yes
# Hosted Agent / Toolbox / 接続は Foundry ポータル（pj-seall-hackthon）で削除
```
Foundry account 自体は従量課金で idle コストは小さい。

## タスク状況
| Task | 内容 | 状態 |
|---|---|---|
| 001 | baseline と契約 | ✅ |
| 004 | Hosted Agent scaffold | ✅ deployed |
| 005 | Fabric Data Agent tool | ✅ 営業 live 検証 |
| 006 | Foundry IQ + Toolbox | ✅ deploy + retrieval 検証 |
| 007 | factory/sales モード + 堅牢性テスト | ✅ |
| 002 | telemetry lot 安定化 | ✅ 工場 live 復旧（`seed_lakehouse_telemetry_direct.py` で lot 固定の異常を再現）+ E2E 検証 |
| 008–011 | Teams 公開 / Power Automate / Cowork / Copilot Studio | 外部環境セットアップが必要（specs は各ディレクトリに既存） |
| 012 | デモ統合 | 本書 |
