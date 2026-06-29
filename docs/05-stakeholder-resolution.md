# 正式担当者の特定

## 「担当者の特定」の意味

異常の内容から、誰に通知し、誰を必須会議参加者にするかを正式な対応表から決めること。
AIが名前を推測することではない。

## 2種類を分ける

### 正式担当者

- 工場品質責任者
- ライン責任者
- 設備保全責任者
- 生産計画担当
- 担当営業
- 物流担当

`StakeholderRouting`から決定する。

### 任意の有識者候補

過去資料の作成者や最近の関連会議参加者など。
CoworkやWork IQで提案してもよいが、正式責任者の代わりにはしない。

## SharePoint List: StakeholderRouting

列:

```text
routing_id
role_code
scope_type
plant_id
line_id
customer_name
product_number
user_upn
is_primary
priority
active
```

## role_code

```text
factory_quality_owner
line_owner
maintenance_owner
production_planner
logistics_owner
sales_owner
sales_manager
global_fallback
```

## scope_type

```text
plant_line
plant
customer_product
customer
product
global
```

## 解決順

### 工場品質責任者

1. role + plant + line
2. role + plant
3. role + global

### 担当営業

1. role + customer + product
2. role + customer
3. role + product
4. role + global

各段階で複数該当した場合:

1. `active=true`
2. specificityが高い
3. `is_primary=true`
4. `priority`が小さい
5. `routing_id`の昇順

## fallback

該当者がいない場合は`global_fallback`へ通知し、Work Packageへ警告を残す。

## Coworkへの引き渡し

Coworkには役割名だけでなく、Power Automateで確定したUPNを渡す。

```json
{
  "required_attendees": [
    {"role_code": "factory_quality_owner", "user_upn": "quality@example.com"},
    {"role_code": "maintenance_owner", "user_upn": "maintenance@example.com"}
  ]
}
```

Coworkは空き時間を探すが、正式担当者は変更しない。
