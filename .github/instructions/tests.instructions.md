---
applyTo: "agent/tests/**/*.py,routing/tests/**/*.py,contracts/samples/**,evals/**"
---

- テストはネットワークへ接続しない。
- product-level orderがcandidateになることを必ずテストする。
- hypothesis.statusがunverifiedであることをテストする。
- 正式担当者の優先順位とfallbackをテストする。
- FabricまたはFoundry IQ失敗時にwarningsが返ることをテストする。
- fixtureへ実テナント名や実メールアドレスを入れない。
