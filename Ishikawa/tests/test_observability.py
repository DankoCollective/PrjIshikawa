from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ishikawa.http_listener import ListenerEvent
from ishikawa.observability import (
    LOG_PROFILES,
    ClassifiedEvent,
    ContentFreeMetric,
    ConfiguredObservability,
    ObservabilityContractError,
    ProtectedJSONLWriter,
    VerboseActivation,
    validate_logging_profile,
)
from ishikawa.retrieval_service import RetrievalOperationalTelemetry
from ishikawa.yaml_loader import load_restricted_yaml


def identity(character: str) -> str:
    return character * 64


class MutableClock:
    def __init__(self):
        self.value = datetime(2026, 10, 21, 0, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.value


class ObservabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.raw_profile = load_restricted_yaml(
            root / "config/templates/logging_profile.yaml",
            label="logging profile",
        )

    def policy(self, **updates):
        raw = copy.deepcopy(self.raw_profile)
        raw.update(updates)
        return validate_logging_profile(raw)

    def records(self, path: Path):
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]

    def test_template_freezes_three_profiles_and_protected_limits(self):
        policy = self.policy()
        self.assertEqual(LOG_PROFILES, ("default", "debug", "verbose"))
        self.assertEqual(policy.base_profile, "default")
        self.assertEqual(policy.operational_filename, "retrieval.jsonl")
        self.assertEqual(policy.metrics_filename, "metrics.jsonl")
        self.assertEqual(policy.audit_filename, "audit.jsonl")
        self.assertEqual(policy.retained_file_count, 5)
        self.assertEqual(policy.maximum_verbose_seconds, 3600)
        self.assertEqual(policy.operational_retention_days, 30)
        self.assertEqual(policy.metrics_retention_days, 30)
        self.assertEqual(policy.audit_retention_days, 90)
        self.assertEqual(len(policy.digest), 64)

    def test_unknown_static_profile_fields_and_paths_fail_closed(self):
        for update in (
            {"base_profile": "verbose"},
            {"base_profile": "trace"},
            {"operational_filename": "../retrieval.jsonl"},
            {"audit_filename": "retrieval.jsonl"},
            {"metrics_filename": "retrieval.jsonl"},
            {"operational_retention_days": 0},
            {"metrics_retention_days": 3651},
            {"audit_retention_days": "90"},
        ):
            with self.subTest(update=update), self.assertRaises(ObservabilityContractError):
                self.policy(**update)
        unknown = copy.deepcopy(self.raw_profile)
        unknown["capture_headers"] = True
        with self.assertRaises(ObservabilityContractError):
            validate_logging_profile(unknown)

    def test_listener_writes_only_low_cardinality_content_free_metrics(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir(mode=0o700)
            observability = ConfiguredObservability(self.policy(), log_root, clock)
            telemetry = RetrievalOperationalTelemetry(
                lane_states=(("exact", "not_applicable"), ("lexical", "pass"), ("vector", "pass")),
                fused_candidate_count=7,
                authorized_candidate_count=5,
                reconstructed_unit_count=3,
                citation_count=4,
                prompt_token_count=512,
                answer_token_reserve=512,
                context_tokens_used=1024,
                context_token_limit=32768,
                nomic_query_tokens=12,
            )
            observability.listener_event(
                ListenerEvent(
                    identity("e"),
                    "application_answered",
                    200,
                    17,
                    ("request-accepted", "generation-retry", "response-built"),
                    (
                        ("request-accepted", 2),
                        ("generation-retry", 1),
                        ("response-built", 14),
                    ),
                    telemetry,
                )
            )
            path = log_root / "metrics.jsonl"
            records = self.records(path)
            self.assertEqual(len(records), 18)
            self.assertTrue(
                all(record["schema"] == "ishikawa.metric-event.v1" for record in records)
            )
            self.assertEqual(
                records[0]["labels"],
                {"category": "application", "outcome": "answered"},
            )
            self.assertEqual(
                [
                    record["labels"]
                    for record in records
                    if record["metric_name"] == "retrieval_lane_state_total"
                ],
                [
                    {"lane": "exact", "state": "not_applicable"},
                    {"lane": "lexical", "state": "pass"},
                    {"lane": "vector", "state": "pass"},
                ],
            )
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertNotIn("question", path.read_text(encoding="utf-8"))
            self.assertIn(
                {"stage": "generation-retry"},
                [
                    record["labels"]
                    for record in records
                    if record["metric_name"] == "pipeline_stage_completed_total"
                ],
            )

    def test_metric_names_labels_values_and_stage_alignment_fail_closed(self):
        for metric in (
            ContentFreeMetric("unknown", 1, identity("f"), {}),
            ContentFreeMetric(
                "requests_total",
                1,
                identity("f"),
                {"category": "application", "outcome": "user-controlled"},
            ),
            ContentFreeMetric("citation_count", -1, identity("f"), {}),
            ContentFreeMetric(
                "retrieval_lane_state_total",
                1,
                identity("f"),
                {"lane": "custom", "state": "pass"},
            ),
        ):
            with self.subTest(metric=metric), self.assertRaises(ObservabilityContractError):
                metric.validated()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(self.policy(), log_root)
            with self.assertRaises(ObservabilityContractError):
                observability.listener_event(
                    ListenerEvent(
                        identity("f"),
                        "application_answered",
                        200,
                        1,
                        ("request-accepted",),
                        (("response-built", 1),),
                    )
                )

    def test_default_listener_log_is_operational_only_and_protected(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir(mode=0o700)
            observability = ConfiguredObservability(self.policy(), log_root, clock)
            observability.listener_event(
                ListenerEvent(
                    identity("a"),
                    "application_answered",
                    200,
                    17,
                    ("request-accepted", "generation-complete"),
                )
            )
            path = log_root / "retrieval.jsonl"
            record = self.records(path)[0]
            self.assertEqual(record["classification"], ["operational"])
            self.assertEqual(record["profile"], "default")
            self.assertEqual(record["request_id"], identity("a"))
            self.assertEqual(record["duration_ms"], 17)
            self.assertNotIn("diagnostic", record)
            self.assertNotIn("restricted", record)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)

    def test_debug_adds_only_allowlisted_diagnostics(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(
                self.policy(base_profile="debug"), log_root, clock
            )
            observability.operational.write(
                ClassifiedEvent(
                    "retrieval-api",
                    "retrieval",
                    "RETRIEVAL_COMPLETED",
                    "info",
                    "completed",
                    request_id=identity("b"),
                    diagnostic={"lane_counts": {"exact": 1, "lexical": 2, "vector": 3}},
                    restricted={"question": "This must stay excluded."},
                )
            )
            record = self.records(log_root / "retrieval.jsonl")[0]
            self.assertEqual(record["classification"], ["operational", "diagnostic"])
            self.assertEqual(record["diagnostic"]["lane_counts"]["vector"], 3)
            self.assertNotIn("restricted", record)

    def test_debug_listener_records_grounded_generation_retry_state(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(
                self.policy(base_profile="debug"), log_root, clock
            )
            observability.listener_event(
                ListenerEvent(
                    identity("b"),
                    "application_answered",
                    200,
                    17,
                    ("request-accepted", "generation-retry", "response-built"),
                )
            )
            record = self.records(log_root / "retrieval.jsonl")[0]
            self.assertEqual(
                record["diagnostic"]["retry_state"],
                "grounded_generation_retried",
            )

    def test_verbose_is_request_scoped_bounded_and_automatically_restored(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(self.policy(), log_root, clock)
            observability.activate_verbose(
                VerboseActivation(
                    "investigate_response",
                    identity("c"),
                    clock.value,
                    clock.value + timedelta(minutes=5),
                )
            )
            for request_id in (identity("d"), identity("c")):
                observability.operational.write(
                    ClassifiedEvent(
                        "retrieval-api",
                        "generation",
                        "GENERATION_COMPLETED",
                        "info",
                        "completed",
                        request_id=request_id,
                        restricted={"answer": "classified troubleshooting content"},
                    )
                )
            clock.value += timedelta(minutes=6)
            observability.operational.write(
                ClassifiedEvent(
                    "retrieval-api",
                    "generation",
                    "GENERATION_COMPLETED",
                    "info",
                    "completed",
                    request_id=identity("c"),
                    restricted={"answer": "expired content"},
                )
            )
            records = self.records(log_root / "retrieval.jsonl")
            self.assertEqual([record["profile"] for record in records], ["default", "verbose", "default"])
            self.assertNotIn("restricted", records[0])
            self.assertIn("restricted", records[1])
            self.assertNotIn("restricted", records[2])
            audit = self.records(log_root / "audit.jsonl")
            self.assertEqual(audit[0]["event_code"], "VERBOSE_CAPTURE_ENABLED")
            self.assertEqual(audit[0]["reason_code"], "investigate_response")
            self.assertEqual(audit[0]["scope"], "request")
            self.assertNotIn("classified troubleshooting content", json.dumps(audit[0]))

    def test_verbose_interval_and_emergency_stop_are_enforced(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(self.policy(), log_root, clock)
            with self.assertRaises(ObservabilityContractError):
                observability.activate_verbose(
                    VerboseActivation(
                        "investigate_response",
                        "service",
                        clock.value,
                        clock.value + timedelta(seconds=3601),
                    )
                )
            observability.activate_verbose(
                VerboseActivation(
                    "investigate_response",
                    "service",
                    clock.value,
                    clock.value + timedelta(minutes=5),
                )
            )
            self.assertEqual(observability.controller.active_profile(), "verbose")
            observability.stop_verbose()
            self.assertEqual(observability.controller.active_profile(), "default")

    def test_unclassified_and_record_forging_fields_are_rejected(self):
        with self.assertRaises(ObservabilityContractError):
            ClassifiedEvent(
                "retrieval-api",
                "request",
                "REQUEST_RECEIVED",
                "info",
                "accepted",
                diagnostic={"authorization": "Bearer secret"},
            ).validated()
        with self.assertRaises(ObservabilityContractError):
            ClassifiedEvent(
                "retrieval-api",
                "request",
                "REQUEST_RECEIVED",
                "info",
                "accepted\nforged",
            ).validated()

    def test_json_encoding_prevents_record_forgery(self):
        clock = MutableClock()
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            observability = ConfiguredObservability(self.policy(), log_root, clock)
            observability.activate_verbose(
                VerboseActivation(
                    "investigate_response",
                    "service",
                    clock.value,
                    clock.value + timedelta(minutes=5),
                )
            )
            observability.operational.write(
                ClassifiedEvent(
                    "retrieval-api",
                    "request",
                    "REQUEST_RECEIVED",
                    "info",
                    "accepted",
                    restricted={"question": "line one\n{\"forged\":true}"},
                )
            )
            raw = (log_root / "retrieval.jsonl").read_text(encoding="utf-8")
            self.assertEqual(len(raw.splitlines()), 1)
            self.assertIn("\n", json.loads(raw)["restricted"]["question"])

    def test_rotation_is_bounded_and_symlink_destinations_are_rejected(self):
        policy = self.policy(
            maximum_event_bytes=1024,
            maximum_file_bytes=1100,
            retained_file_count=3,
        )
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            writer = ProtectedJSONLWriter(log_root, policy.operational_filename, policy)
            for index in range(5):
                writer.append({"index": index, "padding": "x" * 700})
            self.assertTrue((log_root / "retrieval.jsonl").is_file())
            self.assertTrue((log_root / "retrieval.jsonl.1").is_file())
            self.assertTrue((log_root / "retrieval.jsonl.2").is_file())
            self.assertFalse((log_root / "retrieval.jsonl.3").exists())
            self.assertEqual(
                os.stat(log_root / ".retrieval.jsonl.lock").st_mode & 0o777,
                0o600,
            )

        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = Path(temporary_root) / "logs"
            log_root.mkdir()
            target = Path(temporary_root) / "outside"
            target.write_text("outside", encoding="utf-8")
            (log_root / "retrieval.jsonl").symlink_to(target)
            writer = ProtectedJSONLWriter(log_root, policy.operational_filename, policy)
            with self.assertRaises(ObservabilityContractError):
                writer.append({"safe": True})


if __name__ == "__main__":
    unittest.main()
