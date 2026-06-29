# デモランブック

1. Dashboardで平常運転を表示
2. CRCA / ST-07-PRESS / 固定lotへ異常注入
3. Activatorが工場担当者へTeams通知
4. 工場担当者がHosted Agentでfactory調査
5. Fabricの異常・受注候補とFoundry IQ文書を表示
6. 製品一致は影響候補であると説明
7. 工場担当者が営業確認を承認
8. StakeholderRoutingで担当営業を決定しTeams通知
9. sales調査
10. Coworkが必須参加者の会議と資料を作成

フォールバック:
- Activator失敗: 手動Teams通知
- Fabric Data Agent失敗: fixture
- Teams公開失敗: Foundry Playground
- Foundry IQ失敗: fixture文書結果
- Power Automate失敗: 固定営業担当へ手動通知
- Cowork失敗: 事前作成成果物と録画
