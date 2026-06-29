# Fabric Data Agent設定

1. Eventhouse KQL DB `eh_manufacturing_rti`をData sourceとして追加する。
2. `scenario-c/queries/agent_context.kql`の関数を登録する。
3. `instructions.md`をAgent instructionsへ設定する。
4. `example-queries.yaml`の質問とKQLを例示として登録する。
5. Data Agentを公開する。
6. Foundry projectのConnected resourcesでMicrosoft Fabric connectionを作る。
7. Connection IDを`FABRIC_PROJECT_CONNECTION_ID`へ設定する。

確認:
- fixed lotの異常文脈が返る
- order impactがcandidateになる
- 最大10件
