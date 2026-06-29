# Activator直接通知とPower Automateの使い分け

## Path A: ActivatorからTeamsへ直接通知

用途:
- 最初の異常通知
- Dashboardリンク
- AI調査を開始する案内

長所:
- 既存実装を活用できる
- 構成が短い
- デモ失敗点が少ない

制約:
- 通知は業務プロセスの状態管理ではない
- 工場判断を待つ、正式担当者を探す、営業へ通知する処理には向かない
- ボタンや詳細なAdaptive Cardが必要な場合はPower Automateの方が作りやすい

## Path B: Activator Custom ActionからPower Automate

用途:
- incident_id生成
- QualityIncidentsへの保存
- Adaptive Card
- 工場判断の保存
- StakeholderRouting検索
- 営業通知
- Cowork Work Package作成

## 推奨する導入順

```text
Day 1-2: Path AでAgentまで通す
Day 3-4: 必要な業務引き継ぎだけPath Bで追加
```

Power Automateに原因分析や生成AIの判断を実装しない。
