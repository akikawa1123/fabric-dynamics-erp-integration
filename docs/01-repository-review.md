# 既存リポジトリの再レビュー

確認日: 2026-06-25
対象: `akikawa1123/fabric-dynamics-erp-integration` の `main`

## 既に利用できるもの

`scenario-c/`には次がある。

- Eventstreamによるテレメトリ取り込み
- Eventhouse / KQL Database
- LakehouseへのTelemetry直送
- ERP LakehouseへのOneLake Shortcut
- KQL / T-SQLによる異常、進行中受注、返品の複合分析
- Real-Time Dashboard
- ActivatorとTeams直接通知
- 平常→異常→回復のテレメトリ送信器
- デモランブック

Microsoft Foundry担当はFabric基盤を作り直さず、既存データ面と接続する。

## 修正が必要な点

### 1. 異常フェーズ内でlot_idを固定する

現在の送信器はイベント生成ごとにlot IDを作るため、同じ異常フェーズが複数ロットへ分散する。

Task 002で次を追加する。

- `--anomaly-lot-id`
- 未指定時は異常フェーズ開始時に1回だけ生成
- 異常対象product / stationでは同じlotを使用

### 2. Activatorのオブジェクト粒度

現在の設計はstation単位の集約が中心である。複数製品・ロットが同じstationを流れるため、
Agentへ渡す文脈は`station + product + lot`単位にする。

### 3. 顧客影響は製品単位の候補

現在のERP突合は返品明細を製品コードと製品GUIDのブリッジにして、
同じ製品の未出荷フルフィルメント受注を抽出する。

対象ロットが販売注文へ引き当てられていることは証明していないため、結果は`candidate`。

### 4. 製品ブリッジの制約

返品履歴に存在しない製品は製品GUIDへ変換できない。
ハッカソンではCRCAへ固定し、汎用化は対象外にする。

### 5. 正式担当者情報がない

既存ERPデータから工場品質担当者や担当営業UPNを安定取得できない。
`StakeholderRouting` SharePoint Listを追加し、決定論的に解決する。

### 6. Activator定義の移植性

Activator定義のAPI importが環境によって失敗する可能性があるため、
ポータルの手動設定手順をフォールバックとして維持する。
