# 設計判断の結論

## 推奨

今回の3〜4日実装では、次の順序にする。

1. 既存ActivatorのTeams直接通知を維持する。
2. Microsoft Foundry Hosted Agentを完成させる。
3. Fabric Data AgentとFoundry IQを接続する。
4. 工場→営業の自動引き継ぎが必要になった時点で、小さなPower Automateフローを追加する。
5. CoworkへSharePointのWork Packageを渡す。
6. Copilot Studioは接続spike成功時だけ入口に追加する。

## Power Automateが不要な範囲

```text
Activator → Teams直接通知 → 利用者がHosted Agentを開く → AI調査
```

異常通知とAI調査だけならPower Automateは不要。

## Power Automateが必要になる範囲

```text
工場判断を保存
→ 正式な営業担当者を決定
→ 営業担当者へ自動通知
→ Cowork Work Packageを作成
```

この処理はAI推論ではなく、状態管理と決定論的な業務ルーティングである。

## Copilot Studioの位置

Copilot StudioはPower Automateの代替ではない。

- Copilot Studio: Teams上の会話、案内、Adaptive Card、Connected Agent
- Power Automate: イベント、状態、正式担当者の決定、通知、ファイル作成
- Microsoft Foundry: 品質調査、根拠統合、仮説、対策案

## Hosted Agent数

1つ。

```text
manufacturing-quality-investigation-agent
  ├─ factory mode
  └─ sales mode
```
