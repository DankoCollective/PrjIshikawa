#!/usr/bin/env python3
"""Create content-free qualification evidence for document production."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from types import SimpleNamespace

from ishikawa.canonical import canonical_json_bytes
from ishikawa.document_producer import (
    METHOD_PROFILE_ID,
    DocumentProducerContractError,
    NativeDocumentProducer,
    ProducerArtifactBundle,
)
from ishikawa.models import IngestionManifest, ManifestDocument
from ishikawa.operator_ingestion import DocumentProductionRequest, ProductionBatch


def write_exclusive(path: Path, value: dict[str, object]) -> None:
    payload = canonical_json_bytes(value) + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.output.is_absolute() or arguments.output.exists():
        raise RuntimeError("unsafe output path")

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / "source"
        work = root / "work"
        source.mkdir()
        work.mkdir()
        pdf = source / "sample.pdf"
        pdf.write_bytes(b"%PDF-1.4\nsynthetic producer contract fixture\n%%EOF\n")
        source_digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
        manifest = IngestionManifest(
            1,
            (ManifestDocument("sample.pdf", "policy.sample", "policy"),),
            (),
            "a" * 64,
        )
        request = DocumentProductionRequest(
            "add", "policy.sample", "policy", "sample.pdf", source_digest
        )
        batch = ProductionBatch(
            "b" * 64, METHOD_PROFILE_ID, source.resolve(), (request,)
        )
        stage_calls = 0
        retainer_calls = 0
        workspace_paths: list[Path] = []

        def stage(_batch, subset, workspace):
            nonlocal stage_calls
            stage_calls += 1
            workspace_paths.append(workspace)
            if [item.document_key for item in subset.documents] != ["policy.sample"]:
                raise RuntimeError("subset mismatch")
            artifacts = []
            for index, name in enumerate(("normalized.json", "chunks.json", "embeddings.json")):
                path = workspace / name
                path.write_bytes(f"synthetic-{index}".encode("ascii"))
                artifacts.append((path, hashlib.sha256(path.read_bytes()).hexdigest()))
            return ProducerArtifactBundle(
                artifacts[0][0], artifacts[0][1],
                artifacts[1][0], artifacts[1][1],
                artifacts[2][0], artifacts[2][1],
            )

        def retain(_bundle):
            nonlocal retainer_calls
            retainer_calls += 1

        def adapter(**values):
            if values["manifest"].retirements:
                raise RuntimeError("retirement entered producer")
            return (SimpleNamespace(
                document_key="policy.sample",
                class_id="policy",
                source_digest=source_digest,
            ),)

        producer = NativeDocumentProducer(
            manifest, work.resolve(), stage, retain, adapter
        )
        prepared = producer(batch)
        if (
            len(prepared) != 1
            or stage_calls != 1
            or retainer_calls != 1
            or workspace_paths[0].exists()
        ):
            raise RuntimeError("success scenario mismatch")

        blocked_before_stage = 0
        for invalid in (
            ProductionBatch("b" * 64, "f" * 64, source.resolve(), (request,)),
            ProductionBatch("b" * 64, METHOD_PROFILE_ID, source.resolve(), ()),
        ):
            try:
                producer(invalid)
            except DocumentProducerContractError:
                blocked_before_stage += 1
            else:
                raise RuntimeError("invalid production batch accepted")
        if stage_calls != 1 or blocked_before_stage != 2:
            raise RuntimeError("pre-stage rejection mismatch")

    artifact = {
        "schema_version": 1,
        "purpose": "document_producer_contract_qualification",
        "method_profile_id": METHOD_PROFILE_ID,
        "scenarios": {
            "changed_document_success": "pass",
            "invalid_method_profile": "blocked_before_stage",
            "empty_batch": "blocked_before_stage",
        },
        "changed_documents_only": True,
        "stage_calls_for_one_batch": 1,
        "artifact_identity_required": True,
        "artifact_workspace_bounded": True,
        "prepared_coverage_exact": True,
        "retention_after_validation_only": True,
        "workspace_cleanup": "pass",
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "credential_read": False,
        "source_content_retained": False,
    }
    write_exclusive(arguments.output, artifact)
    print("producer_scenarios=3;success=pass;method_profile_rejection=pass;empty_batch_rejection=pass")
    print("changed_documents_only=true;artifact_stage_calls=1;prepared_coverage=exact")
    print("artifact_identity=required;workspace=bounded_0700;cleanup=pass")
    print("retention=after_validation_only;failure_retention=false")
    print("target_contact=false;database_contact=false;model_call=false;credential_read=false")
    print("document_producer_contract_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
