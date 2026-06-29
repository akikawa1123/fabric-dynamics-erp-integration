---
applyTo: "power-automate/**,copilot-studio/**,cowork/**,routing/**,contracts/**/*routing*"
---

- 初回通知と業務ルーティングを分けて設計する。
- 正式担当者は`StakeholderRouting`の決定論的な優先順位で決める。
- ルーティングに失敗した場合はglobal fallbackへ送る。
- Coworkへ渡す前に必須参加者UPNを確定する。
- 送信、会議作成、投稿には人の承認境界を残す。
- Power AutomateをAI推論に使わない。
