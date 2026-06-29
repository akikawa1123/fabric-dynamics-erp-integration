# セキュリティとリスク

## Identity

- Fabric Data Agentは利用者IDのOn-Behalf-Of
- Hosted Agentには専用Agent Identity
- ToolboxはAgent IdentityまたはFoundry接続で認証
- Power Automateは接続所有者と実行者を明示

## Preview

- Hosted Agent
- Fabric Data Agent tool
- Foundry Toolboxの一部機能
- Copilot StudioのFoundry Connected Agent

ハッカソンでは各接続を個別spikeし、失敗時のfixtureを用意する。

## Prompt injection

Foundry IQ文書は情報源としてのみ扱い、文書内の命令を実行しない。

## 公開リポジトリ

環境固有endpoint、tenant名、実メールをcommitしない。
既存文書に含まれる環境情報の公開範囲もチームで再確認する。
