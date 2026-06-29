from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, HttpUrl


class Operation(StrEnum):
    FACTORY = "factory_investigation"
    SALES = "sales_investigation"


class Persona(StrEnum):
    FACTORY = "factory"
    SALES = "sales"


class ImpactClassification(StrEnum):
    CONFIRMED = "confirmed"
    CANDIDATE = "candidate"
    NOT_AFFECTED = "not_affected"


class EvidenceSource(StrEnum):
    INCIDENT_EVENT = "incident_event"
    FABRIC = "fabric"
    FOUNDRY_IQ = "foundry_iq"
    HUMAN = "human"


class ToolName(StrEnum):
    FABRIC = "fabric_data_agent"
    FOUNDRY_IQ = "foundry_iq"


class ToolState(StrEnum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    SKIPPED = "skipped"


class Anomaly(BaseModel):
    model_config = ConfigDict(extra="forbid")

    metric_name: str
    observed_value: float
    threshold_value: float
    unit: str
    failure_count: int = Field(default=0, ge=0)
    total_count: int = Field(default=0, ge=0)
    defect_rate: float | None = Field(default=None, ge=0, le=1)


class InvestigationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str = "1.0"
    operation: Operation
    incident_id: str = Field(pattern=r"^QI-[0-9]{8}-[0-9]{3,}$")
    detected_at: datetime
    plant_id: str
    line_id: str
    station_id: str
    product_number: str
    lot_id: str
    anomaly: Anomaly
    dashboard_url: HttpUrl | None = None


class Fact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    statement: str
    source_type: EvidenceSource
    source_id: str
    source_title: str | None = None
    source_url: HttpUrl | None = None
    observed_at: datetime | None = None


class DocumentEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    summary: str
    document_id: str
    document_title: str
    source_url: HttpUrl | None = None


class AffectedOrder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sales_order_id: str
    customer_name: str
    impact_classification: ImpactClassification
    reason: str
    product_number: str | None = None
    planned_ship_date: datetime | None = None
    affected_quantity: float | None = None


class Hypothesis(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    statement: str
    confidence: str
    status: str = "unverified"
    supporting_evidence_ids: list[str] = Field(default_factory=list)


class RecommendedAction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    priority: int = Field(ge=1)
    action: str
    owner_role: str
    requires_human_approval: bool = True


class ToolExecutionStatus(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tool: ToolName
    state: ToolState
    detail: str | None = None


class Assessment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    incident_id: str
    persona: Persona
    confirmed_facts: list[Fact] = Field(default_factory=list)
    affected_orders: list[AffectedOrder] = Field(default_factory=list)
    document_evidence: list[DocumentEvidence] = Field(default_factory=list)
    hypotheses: list[Hypothesis] = Field(default_factory=list)
    recommended_actions: list[RecommendedAction] = Field(default_factory=list)
    open_questions: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    tool_status: list[ToolExecutionStatus] = Field(default_factory=list)


class ScopeType(StrEnum):
    PLANT_LINE = "plant_line"
    PLANT = "plant"
    CUSTOMER_PRODUCT = "customer_product"
    CUSTOMER = "customer"
    PRODUCT = "product"
    GLOBAL = "global"


class RoleCode(StrEnum):
    FACTORY_QUALITY_OWNER = "factory_quality_owner"
    LINE_OWNER = "line_owner"
    MAINTENANCE_OWNER = "maintenance_owner"
    PRODUCTION_PLANNER = "production_planner"
    LOGISTICS_OWNER = "logistics_owner"
    SALES_OWNER = "sales_owner"
    SALES_MANAGER = "sales_manager"
    GLOBAL_FALLBACK = "global_fallback"


class RoutingContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    plant_id: str | None = None
    line_id: str | None = None
    customer_name: str | None = None
    product_number: str | None = None


class StakeholderRoutingRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    routing_id: str
    role_code: RoleCode
    scope_type: ScopeType
    plant_id: str | None = None
    line_id: str | None = None
    customer_name: str | None = None
    product_number: str | None = None
    user_upn: str
    is_primary: bool = False
    priority: int = Field(default=100, ge=0)
    active: bool = True


class ResolvedStakeholder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role_code: RoleCode
    user_upn: str
    routing_id: str
    resolution_reason: str


class MeetingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str
    duration_minutes: int = Field(ge=15)
    required_attendees: list[ResolvedStakeholder]
    agenda: list[str]


class WorkPackage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str = "1.0"
    work_package_id: str
    incident_id: str
    persona: Persona
    assignee_upn: str
    assessment_uri: str
    meeting: MeetingRequest
    artifacts: list[str]
    safety_notes: list[str] = Field(default_factory=list)
