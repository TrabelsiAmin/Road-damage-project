"""Pydantic schemas for TariqMap backend API."""
from __future__ import annotations

from typing import Any
from pydantic import BaseModel, Field


class BoundingBoxSchema(BaseModel):
    x:      float = Field(ge=0.0, le=1.0)
    y:      float = Field(ge=0.0, le=1.0)
    width:  float = Field(ge=0.0, le=1.0)
    height: float = Field(ge=0.0, le=1.0)


class DetectionSchema(BaseModel):
    agent:              str = Field(min_length=1, max_length=64)
    classCode:          str = Field(min_length=1, max_length=32)
    classLabel:         str | None = None
    confidence:         float = Field(ge=0.0, le=1.0)
    box:                BoundingBoxSchema
    frameIndex:         int | None = None
    modelBundleVersion: str | None = None
    timestamp:          str | None = None


class AgentResultSchema(BaseModel):
    agent:      str = Field(min_length=1, max_length=64)
    detections: list[DetectionSchema] = []
    error:      str | None = None
    isMock:     bool = True
    latencyMs:  int | None = None


class ObservationUpload(BaseModel):
    """Mobile → server payload. Field names match mobile app JSON output."""
    id:                 str = Field(min_length=1, max_length=128)
    captureId:          str = Field(min_length=1, max_length=128)
    imagePath:          str = Field(min_length=1, max_length=1024)
    createdAt:          str = Field(min_length=1, max_length=64)
    latitude:           float = Field(ge=-90.0, le=90.0)
    longitude:          float = Field(ge=-180.0, le=180.0)
    accuracyMeters:     float | None = Field(default=None, ge=0.0, le=100000.0)
    actor:              str = Field(min_length=1, max_length=128)
    organizationId:     str | None = None
    syncStatus:         str = "pending"
    mediaSyncStatus:    str = "pending"
    modelBundleVersion: str | None = None
    deviceId:           str | None = None
    imageWidth:         int | None = Field(default=None, ge=0, le=20000)
    imageHeight:        int | None = Field(default=None, ge=0, le=20000)
    priorityScore:      float | None = None
    priorityLabel:      str | None = None
    failedAgents:       int = 0
    agentResults:       list[AgentResultSchema] = []


class HealthResponse(BaseModel):
    status:             str
    server_time:        str
    observation_count:  int


class StatsResponse(BaseModel):
    total:       int
    by_actor:    dict[str, int]
    by_priority: dict[str, int]
    by_class:    dict[str, int]
