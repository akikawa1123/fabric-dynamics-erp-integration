"""Foundry Hosted Agent entry-point (Responses Protocol).

公式 01-basic sample (microsoft-foundry/foundry-samples) の main.py を起点に、
ドメインコードへ委譲する形へ統合した。Microsoft Agent Framework / Azure SDK 連携は
``manufacturing_quality_agent.integrations`` に隔離している（このファイルはSDKを直接importしない）。

このファイルは ``agent.yaml`` の ``code_configuration.entry_point`` であり、
``azd ai agent run`` および Foundry Hosted Agent ランタイムは ``python main.py`` で起動する。
パッケージ ``manufacturing_quality_agent`` は同じデプロイ用ディレクトリ（azure.yaml の
``project: src``）に同梱されるため import 解決できる。
"""

from manufacturing_quality_agent.integrations.host import run

if __name__ == "__main__":
    run()
