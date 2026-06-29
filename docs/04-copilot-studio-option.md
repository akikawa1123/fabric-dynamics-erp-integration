# Copilot Studioを追加する場合

## 役割

Copilot StudioはTeams上の親エージェントとして使う。

- 工場調査 / 営業調査の案内
- インシデント文脈の収集
- Foundry Connected Agentの呼び出し
- Adaptive Card
- Power Automate / Agent Flowの呼び出し

## Foundryへ残すもの

- Fabric Data Agentのツール指示
- Foundry IQ検索
- 事実と仮説の分離
- Assessment Schema
- 工場・営業の専門プロンプト

## 注意

Copilot Studio → Foundry Hosted Agent → Fabric Data Agentという多段経路で、
利用者IDが期待どおりFabricまで伝播するかは実機確認する。

Go条件:
- Connected Agentが成功
- Teams利用者でFabric Data Agentが成功
- デモ待ち時間が許容範囲

No-Go時:
- FoundryからTeamsへ直接公開する構成を維持
