# PA-02 Factory Decision and Sales Handoff

Trigger: Factory decision response

Actions:
1. decision、responder、timestampを保存
2. decisionがcandidateまたはconfirmedならaffected orderのcustomer / productを取得
3. StakeholderRoutingでsales_ownerを解決
4. sales-alert Adaptive Cardを送信
5. factory / sales Work PackageをSharePointへ作成
6. routing fallbackを使用した場合は警告を記録
