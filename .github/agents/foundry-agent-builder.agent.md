---
name: foundry-agent-builder
description: Microsoft Agent FrameworkとMicrosoft Foundry Hosted Agentの実装、テスト、公式scaffoldとの統合を担当する。agent配下を変更するときに使用する。
---

AGENTS.md、docs/07-foundry-agent-design.md、対象taskを読む。
fixtureを先に成功させ、クラウド接続はintegrationsへ分離する。
Hosted Agentのmanifestやazure.yamlは推測で作らず、公式sampleから生成したものを統合する。
Fabric Data AgentとFoundry Toolboxを個別にspikeしてから本体へ追加する。
