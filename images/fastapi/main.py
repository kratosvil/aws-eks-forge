import os
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="eks-forge-fastapi")

APP_VERSION = os.getenv("APP_VERSION", "v1")
POD_NAME    = os.getenv("POD_NAME", "unknown")
NODE_NAME   = os.getenv("NODE_NAME", "unknown")
DEPLOYMENT  = os.getenv("DEPLOYMENT_SLOT", "blue")  # blue or green


class InfoResponse(BaseModel):
    version:    str
    pod:        str
    node:       str
    deployment: str
    message:    str


class HealthResponse(BaseModel):
    status:  str
    version: str
    pod:     str


@app.get("/", response_model=InfoResponse)
def root():
    return InfoResponse(
        version=APP_VERSION,
        pod=POD_NAME,
        node=NODE_NAME,
        deployment=DEPLOYMENT,
        message=f"Hello from eks-forge [{DEPLOYMENT.upper()}]",
    )


@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="healthy",
        version=APP_VERSION,
        pod=POD_NAME,
    )


@app.get("/version")
def version():
    return {
        "version":    APP_VERSION,
        "deployment": DEPLOYMENT,
        "pod":        POD_NAME,
        "node":       NODE_NAME,
    }


@app.get("/items")
def items():
    # BUG intencional v2 — simula fallo en nuevo endpoint
    raise Exception("Internal error: database connection failed")
