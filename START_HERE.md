# 実装開始ガイド

このキットは、次のチームリポジトリへ相乗りするための追加ファイル一式です。

```text
https://github.com/akikawa1123/fabric-dynamics-erp-integration
```

既存の`scenario-c/`はFabric担当の成果物として維持し、Microsoft Foundry担当のコード、
データ契約、GitHub Copilot CLI向け命令、Power Automate／Copilot Studio／Cowork連携設計を追加します。

## まず採用する構成

```text
Fabric RTI / Activator
  ├─ 最初はTeamsへ直接通知
  └─ 自動ルーティングを追加するときだけPower Automate Custom Action
          ↓
Teamsの利用者
          ↓
Microsoft Foundry Hosted Agent（1つ）
  ├─ factory mode
  ├─ sales mode
  ├─ Fabric Data Agent
  └─ Foundry Toolbox / Foundry IQ
          ↓
Power Automate（任意だが、工場→営業の自動連携では推奨）
  ├─ 工場判断を記録
  ├─正式担当者をStakeholderRoutingから決定
  ├─ 営業へTeams通知
  └─ Cowork Work PackageをSharePointへ作成
          ↓
Copilot Cowork
  ├─ 必須参加者の予定確認
  ├─ Teams会議作成
  ├─ Word / Excel / PowerPoint作成
  └─ メール・Teams投稿
```

Copilot Studioはコア完成後の任意入口です。同じHosted AgentをConnected Agentとして呼びます。

## 1. 作業ブランチ

```powershell
git switch main
git fetch upstream
git merge --ff-only upstream/main
git push origin main
git switch -c feature/foundry-quality-agent
```

## 2. キットをリポジトリ直下へ配置

ZIPを展開し、中身をリポジトリ直下へコピーします。

配置後の主な追加物:

```text
agent/
contracts/
fabric-data-agent/
power-automate/
copilot-studio/
cowork/
routing/
docs/
tasks/
.github/
AGENTS.md
```

## 3. ローカルfixture確認

```powershell
cd agent
uv python install 3.13
uv sync --extra dev
uv run python scripts/export_schemas.py --check
uv run pytest
uv run mq-agent-fixture factory ..\contracts\samples\investigation-request.json
uv run mq-agent-fixture sales ..\contracts\samples\investigation-request.json
cd ..
```

## 4. Draft Pull Requestを早めに作る

最初は追加ファイルだけをcommitします。

```powershell
git add AGENTS.md .github agent contracts fabric-data-agent power-automate copilot-studio cowork routing docs tasks START_HERE.md RESOURCE_INDEX.md VERIFICATION.md
git commit -m "chore: add Foundry quality agent implementation kit"
git push -u origin feature/foundry-quality-agent
```

その後、元リポジトリ向けにDraft Pull Requestを作成します。

## 5. GitHub Copilot CLIの最初の依頼

```powershell
copilot
```

```text
AGENTS.md、docs/00-design-decision.md、docs/01-repository-review.md、
docs/05-stakeholder-resolution.md、tasks/001-baseline-and-contracts.mdを読んでください。

最初にコードを変更せず、Task 001について次を示してください。
- 現状
- 変更対象
- 既存scenario-cへの影響
- テスト方法
- ロールバック方法

その後、Task 001だけを実装してください。
製品番号だけで一致した販売注文を顧客影響確認済みにしないでください。
```

## 6. Hosted Agentの公式scaffold

Hosted Agentのホスティングファイルは、変化しやすいmanifestを手書きせず、Task 004で公式sampleから生成します。

```powershell
azd version
azd ext install microsoft.foundry
azd auth login

New-Item -ItemType Directory -Force .generated\hosted-agent | Out-Null
Set-Location .generated\hosted-agent
azd ai agent init -m "https://github.com/microsoft-foundry/foundry-samples/blob/main/samples/python/hosted-agents/agent-framework/responses/01-basic/agent.manifest.yaml" --deploy-mode code
```

生成物を確認後、Copilot CLIに`agent/`へ統合させます。

## 実装順

1. 契約とfixtureを確定する。
2. 異常フェーズのロットとActivator文脈を安定化する。
3. Fabric Data Agent向けKQL関数を追加する。
4. 公式sampleからHosted Agentをscaffoldする。
5. Fabric Data Agentを接続する。
6. Foundry Toolbox / Foundry IQを接続する。
7. 工場・営業モードを完成させる。
8. Teamsへ直接公開する。
9. 必要になった時点でPower Automateによる担当者特定・営業通知を追加する。
10. Cowork連携を追加する。
11. 余裕があればCopilot Studioを入口に追加する。
