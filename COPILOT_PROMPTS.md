# GitHub Copilot CLI用プロンプト

## 計画だけ

```text
AGENTS.mdと対象task、関連docsを読んでください。
コードはまだ変更せず、現状、変更対象、互換性リスク、テスト、ロールバック方法を示してください。
```

## 実装

```text
先ほどの計画に従い、対象taskだけを実装してください。
関係ないファイルを変更しないでください。
完了後にgit diffの要約と実行したテストを報告してください。
```

## 根拠性レビュー

```text
Use the grounding-reviewer role concept to review the factory and sales outputs.
事実、仮説、候補受注、正式担当者、警告の境界を確認し、問題ごとにテストを追加してください。
```

## PRレビュー前

```text
AGENTS.mdを基準に現在の差分をレビューしてください。
秘密情報、既存scenario-cの破壊、candidate/confirmed誤分類、担当者推測、テスト不足を重点確認してください。
コードは変更せず、重大度順に指摘してください。
```
