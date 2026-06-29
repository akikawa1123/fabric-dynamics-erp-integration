# Microsoft Foundry Hosted Agent設計

## 実装

- Microsoft Agent Framework
- FoundryChatClient
- ResponsesHostServer
- Python 3.13
- uv
- Pydantic v2

## Agent

1つのHosted Agentに2モードを持たせる。

### factory

- Fabricから異常値、対象lot、受注候補、返品文脈を取得
- Foundry IQから8D、PFMEA、Control Plan、検査手順を取得
- 封じ込め、追加確認、顧客影響候補を整理

### sales

- Fabricから候補受注、顧客、出荷状態、出荷予定日を取得
- Foundry IQから顧客品質協定、過去初報、報告期限を取得
- 顧客対応会議、資料、通知条件を整理

## Tools

### Fabric Data Agent

Foundry projectのMicrosoft Fabric connection IDを使う。
利用者本人のIDで問い合わせる。

### Foundry Toolbox

Hosted AgentへFoundry管理ツールを直接注入せず、Toolbox MCP endpointへ接続する。
ToolboxにはFoundry IQ Knowledge Baseだけを含める。

## Responses Protocol

会話、Teams公開、セッション管理にResponses Protocolを使う。
`default_options={"store": False}`を設定し、会話履歴の二重保存を避ける。

## 回答

Teamsで標準引用が表示されない場合に備え、回答本文に文書名、文書ID、URLを明示する。
