# Power Automateフロー

## PA-01 Quality Incident Ingress

使用条件:
- Adaptive Cardが必要
- incident stateを保存したい
- 後続ルーティングを自動化したい

Trigger:
- Fabric Activator Custom Action

Actions:
1. incident_id生成
2. QualityIncidentsへ保存
3. StakeholderRoutingから工場品質責任者を解決
4. 工場Adaptive Cardを送信

## PA-02 Factory Decision

Actions:
1. 工場担当者の応答を保存
2. `candidate`または`confirmed`なら営業ルーティング開始
3. 影響対象customer / productを取得
4. StakeholderRoutingからsales ownerを解決
5. 営業Teams通知
6. factory / sales Work Packageを作成

## PA-03 Cowork Work Package

SharePoint libraryへJSONまたはWordを作成する。

Power AutomateはAI調査を行わない。
