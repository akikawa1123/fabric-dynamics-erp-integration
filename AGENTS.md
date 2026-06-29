# AGENTS.md

## 目的

Dynamics 365由来の受注・返品データとMicrosoft Fabric Real-Time Intelligenceの製造テレメトリを統合し、
Microsoft Foundry Hosted Agentが工場・営業向けの根拠付き調査結果を返すハッカソンデモを実装する。

## ディレクトリ責務

- `scenario-c/`: Fabric RTI、Eventstream、Eventhouse、Lakehouse、Dashboard、Activator。既存Fabric担当の責務。
- `fabric-data-agent/`: Fabric Data Agentの設定・例示クエリ。
- `agent/`: Microsoft Agent Frameworkで実装するHosted Agent。
- `contracts/`: Fabric、Teams、Power Automate、Cowork間の契約。
- `routing/`: 正式担当者を決定する決定論的ルーティング。
- `power-automate/`: 通知、工場判断、営業通知、Work Package作成。
- `cowork/`: 会議・資料・メール作成の業務手順。
- `copilot-studio/`: 任意のTeams入口。コア実装へ依存させない。
- `tasks/`: Copilot CLIで1回に実装する変更単位。

## 絶対条件

1. 既存の`scenario-c/`デモを壊さない。
2. Python 3.13と`uv`を使用する。
3. 秘密情報、アクセストークン、接続文字列、実メールアドレスをcommitしない。
4. 確認済み事実、文書根拠、原因仮説、推奨アクション、未確認事項を分離する。
5. 原因仮説は常に`unverified`とする。
6. 製品番号だけが一致する販売注文は`candidate`であり、`confirmed`ではない。
7. ロット引当を確認できない限り顧客影響を確定しない。
8. AIに正式担当者を推測させない。`StakeholderRouting`から決定する。
9. Coworkには決定済みの必須参加者UPNを渡す。Coworkは正式責任者を決めない。
10. 設備停止、出荷停止、ERP更新、メール送信をHosted Agentから自動実行しない。
11. Fabric Data Agentへの質問は英語の固定テンプレートを優先する。
12. 利用者向けの回答は日本語にする。
13. Copilot Studioの有無でAgentの入力・出力契約を変えない。
14. 外部サービスを呼ぶ単体テストを書かない。
15. SDKやmanifestを推測で固定せず、公式sampleからscaffoldしてから統合する。
16. 1回の作業で1つの`tasks/*.md`だけを実装する。
17. `main`へ直接pushしない。feature branchとPull Requestを使う。

## アーキテクチャ判断

- Hosted Agentは1つ。内部モードは`factory`と`sales`。
- Responses Protocolを使う。
- 初回異常通知だけならActivatorからTeamsへ直接送る。
- 工場判断、正式担当者の特定、営業通知、Cowork Work Package作成が必要ならPower Automateを使う。
- Copilot Studioは任意の会話UIであり、Foundryの推論ロジックを複製しない。
- Fabric Data Agentは利用者本人の権限で呼び出す。
- Foundry IQはFoundry Toolbox経由でHosted Agentへ接続する。

## 完了条件

- fixtureモードでfactory / salesの両方を実行できる。
- PydanticモデルとJSON Schemaが同期している。
- candidate / confirmedの境界をテストできる。
- ステークホルダールーティングをローカルで検証できる。
- Hosted Agentを公式scaffoldでローカル起動できる。
- Fabric Data Agentなしでもテストが成功する。
- ツール失敗時に事実を捏造しない。
