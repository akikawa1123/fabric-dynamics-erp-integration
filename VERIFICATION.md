# 検証状況

## このキットでローカル確認するもの

- Python構文
- Pydanticモデル
- JSON Schema同期
- fixture factory / sales
- candidate / confirmed境界
- hypothesis unverified
- StakeholderRouting exact match / fallback
- Adaptive Card JSON
- YAML / JSON構文

## クラウド環境が必要で未検証のもの

- Microsoft Foundry Hosted Agentの実デプロイ
- Fabric Data AgentのOn-Behalf-Of認証
- Foundry Toolbox / Foundry IQ
- Teams直接公開
- Power Automate Custom Action
- Copilot Cowork実行
- Copilot Studio Connected Agent

各接続はtasksの順でspikeし、成功後にuv.lockと環境手順を固定する。

## ローカル実行結果

```text
........                                                                 [100%]
8 passed in 2.01s
```

- factory fixture: 成功
- sales fixture: 成功
- stakeholder routing: 成功
