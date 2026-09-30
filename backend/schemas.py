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
    agent:              str
    classCode:          str
    classId:            str | None = None
    classLabel:         str | None = None
    confidence:         float = Field(ge=0.0, le=1.0)
    box:                BoundingBoxSchema
    bbox:               BoundingBoxSchema | None = None
    detectionId:        str | None = None
    frameIndex:         int | None = None
    modelBundleVersion: str | None = None
    timestamp:          str | None = None
    detectedAt:         str | None = None


class AgentResultSchema(BaseModel):
    agent:      str
    detections: list[DetectionSchema] = []
    error:      str | None = None
    isMock:     bool = True
    latencyMs:  int | None = None


class ObservationUpload(BaseModel):
    """Mobile → server payload. Field names match mobile app JSON output."""
    id:                 str
    captureId:          str
    imagePath:          str
    createdAt:          str
    latitude:           float = Field(ge=-90.0, le=90.0)
    longitude:          float = Field(ge=-180.0, le=180.0)
    gpsAvailable:       bool = True
    sourceVideoPath:    str | None = None
    frameTimestampMs:   int | None = None
    accuracyMeters:     float | None = None
    actor:              str
    syncStatus:         str = "pending"
    modelBundleVersion: str | None = None
    deviceId:           str | None = None
    imageWidth:         int | None = None
    imageHeight:        int | None = None
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
