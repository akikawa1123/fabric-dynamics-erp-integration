# リソース一覧

## 最初に読む

- `START_HERE.md`
- `AGENTS.md`
- `docs/00-design-decision.md`
- `docs/01-repository-review.md`
- `docs/02-target-architecture.md`
- `docs/05-stakeholder-resolution.md`
- `docs/13-implementation-plan-4-days.md`
- `VERIFICATION.md`

## 実装

- `agent/`: Microsoft Agent Framework / Hosted Agentのドメインコードとfixture
- `scenario-c/queries/agent_context.kql`: Fabric Data Agent向けの読み取り専用KQL関数
- `fabric-data-agent/`: Data Agentの設定指示と例示クエリ
- `contracts/`: システム間JSON契約
- `routing/`: 正式担当者を決定するルーティング契約と検証ツール
- `power-automate/`: Activator連携、工場判断、営業通知の仕様
- `cowork/`: 工場・営業向けCowork Skill案
- `copilot-studio/`: 任意の親エージェント構成

## GitHub Copilot CLI

- `.github/copilot-instructions.md`
- `.github/instructions/*.instructions.md`
- `.github/agents/*.agent.md`
- `tasks/*.md`
- `COPILOT_PROMPTS.md`
