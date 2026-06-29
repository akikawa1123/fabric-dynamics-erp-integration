# 4日間の実装計画

## Day 1: 契約・fixture・Fabric文脈

- キット配置、Draft PR
- InvestigationRequest / Assessment確認
- fixtureテスト
- stable lot実装
- Activator集約粒度の見直し
- Agent向けKQL関数追加

終了条件:
- fixture factory / sales成功
- 同一異常フェーズでlot固定
- KQL関数の構文確認

## Day 2: Hosted AgentとFabric Data Agent

- 公式sampleからHosted Agent scaffold
- Agent Frameworkコード統合
- ローカル起動
- Fabric Data Agent作成・公開
- Foundry connection
- Hosted Agentから固定質問

正午No-Go:
- OBOが通らない場合はfixtureをデモ本線にする

## Day 3: Foundry IQとTeams

- 架空文書をKnowledge Baseへ登録
- Toolbox作成
- factory / sales回答
- Teams直接公開
- 回答本文の参照文書確認

## Day 4: 引き継ぎとデモ安定化

- 必要ならPower Automate Custom Action
- StakeholderRouting
- 工場判断→営業通知
- Cowork会議1件・資料1件
- 余裕があればCopilot Studio spike
- 録画・fixture・手動起動フォールバック
