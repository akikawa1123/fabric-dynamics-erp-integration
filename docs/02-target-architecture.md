# 全体アーキテクチャ

## コア

```text
[Telemetry sender]
        ↓
[Fabric Eventstream]
        ↓
[Eventhouse / KQL DB] ── [ERP external tables]
        ├─ Real-Time Dashboard
        ├─ Fabric Data Agent
        └─ Activator
               ├─ Path A: Teams直接通知
               └─ Path B: Custom Action → Power Automate
                                      ↓
                                QualityIncidents
                                      ↓
[Teams user]
        ↓
[Foundry Hosted Agent / Responses]
        ├─ Fabric Data Agent（利用者ID）
        └─ Foundry Toolbox
              └─ Foundry IQ Knowledge Base
        ↓
[Factory / Sales Assessment]
        ↓
[Power Automate coordination]
        ├─ factory decision
        ├─ StakeholderRouting
        ├─ sales notification
        └─ SharePoint Work Package
        ↓
[Copilot Cowork]
        ├─ schedule meeting
        ├─ create documents
        └─ draft/post communications
```

## 任意のCopilot Studio

```text
Teams → Copilot Studio → Connected Agent → Foundry Hosted Agent
```

Copilot Studioを追加しても、Fabric Data Agent、Foundry IQ、Assessment契約はFoundry側に残す。

## 状態保存

MVPではSharePointを使う。

- List: `QualityIncidents`
- List: `StakeholderRouting`
- Library: `ManufacturingQuality/Assessments`
- Library: `ManufacturingQuality/WorkPackages`

本番化時にはDataverseまたは専用APIへ差し替えられるよう、JSON契約を固定する。
