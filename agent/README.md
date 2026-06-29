# Manufacturing Quality Agent

## fixture

```powershell
uv python install 3.13
uv sync --extra dev
uv run python scripts/export_schemas.py --check
uv run pytest
uv run mq-agent-fixture factory ..\contracts\samples\investigation-request.json
uv run mq-agent-fixture sales ..\contracts\samples\investigation-request.json
uv run mq-routing-check ..\routing\stakeholder-routing.sample.csv ..\contracts\samples\routing-context-sales.json sales_owner
```

## Hosted Agent scaffold

manifestを手書きせず、公式sampleから生成する。

```powershell
azd ext install microsoft.foundry
azd ai agent init -m "https://github.com/microsoft-foundry/foundry-samples/blob/main/samples/python/hosted-agents/agent-framework/responses/01-basic/agent.manifest.yaml" --deploy-mode code
```

Task 004で生成物とこの`src/`を統合済み（下記「ローカル実行 / スモークテスト」を参照）。

## ローカル実行 / スモークテスト

統合後のレイアウト（Task 004）:

- `azure.yaml` … azdプロジェクト定義（`project: src` がデプロイZIPのルート、`infra: ./infra`）。
- `src/main.py` … Foundryエントリポイント（Responsesプロトコル）。`manufacturing_quality_agent.integrations.host.run()` へ委譲する薄いラッパー（このファイルはSDKを直接importしない）。
- `src/agent.yaml` … Hosted Agent定義（`runtime: python_3_13`, `entry_point: main.py`, `dependency_resolution: remote_build`）。モデルは未解決プレースホルダ `{{AZURE_AI_MODEL_DEPLOYMENT_NAME}}`（deploy時に解決）。
- `src/requirements.txt` … デプロイ/ローカル実行の実行時依存。
- `src/manufacturing_quality_agent/integrations/` … クラウドSDK（Agent Framework / azure-identity / MCP）を隔離。ドメインモデルにSDK依存を混ぜない。

ローカルで `/responses` を起動してスモークする手順（**デプロイしない**・課金は推論分のみ）:

```powershell
# 1) 環境変数（秘密情報なし。Entra認証 = DefaultAzureCredential、APIキー不要）
$env:FOUNDRY_PROJECT_ENDPOINT = "<your-foundry-project-endpoint>"   # 例: https://<account>.services.ai.azure.com/api/projects/<project>
$env:AZURE_AI_MODEL_DEPLOYMENT_NAME = "gpt-5.4"

# 2) ローカルサーバ起動（ポート8088、ブラウザInspectorは開かない）
azd ai agent run --no-inspector

# 3) 別ターミナルから /responses を1リクエストでスモーク
azd ai agent invoke --local --new-session "こんにちは。あなたの役割を1文で簡潔に教えてください。"
```

> メモ: `azd ai agent run` は `src/.venv` を自前で作成し `requirements.txt` を導入する。ローカルのインタプリタ解決によっては Python 3.14 が選ばれ `requires-python ==3.13.*` の警告が出るが、ローカルスモークは動作する。クラウド実行ランタイムは `agent.yaml` の `runtime: python_3_13` で決まる（このローカルvenvとは独立）。Fabric/Toolbox 変数を未設定にすると、それらのツールは無効化されモデル単体で起動する。
