from __future__ import annotations

import copy
import unittest
from pathlib import Path
from types import SimpleNamespace

from ishikawa.canonical import domain_digest
from ishikawa.errors import IshikawaValidationError
from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
from ishikawa.relationships import (
    ReferenceEvidence,
    ReferenceOwner,
    RelationshipOverride,
    TraversalEdge,
    build_supersedes_edge,
    discover_prepared_relationships,
    expand_one_hop,
    extract_declared_identifiers,
    extract_explicit_references,
    resolve_explicit_references,
    validate_relationship_registry,
)
from ishikawa.yaml_loader import load_restricted_yaml


def identity(label: str) -> str:
    return domain_digest("ishikawa.test-identity.v1", label)


def registry_value():
    path = Path(__file__).resolve().parents[1] / "config" / "templates" / "relationship_types.yaml"
    return load_restricted_yaml(path, label="relationship registry")


def evidence(reference: str = "99 TST 2002", source: str = "policy.alpha") -> ReferenceEvidence:
    return ReferenceEvidence(
        source_document_key=source,
        source_document_identity=identity(source),
        source_document_version_identity=identity(source + ":v1"),
        source_artifact_set_identity=identity(source + ":artifacts"),
        source_structural_unit_identity=identity(source + ":unit:1"),
        evidence_citation_identity=identity(source + ":citation:1"),
        reference_value=reference,
        page_start=1,
    )


class RelationshipTests(unittest.TestCase):
    def setUp(self):
        self.registry = validate_relationship_registry(registry_value())
        self.beta = ReferenceOwner("99 TST 2002", "policy.beta", identity("policy.beta"))

    def assert_reason(self, value, reason):
        with self.assertRaises(IshikawaValidationError) as caught:
            validate_relationship_registry(value)
        self.assertEqual(caught.exception.reason_code, reason)

    def test_template_validates_and_binds_base_profile(self):
        self.assertEqual(self.registry.maximum_hops, 1)
        self.assertEqual(self.registry.traversable_types, ("explicit_reference.document",))
        self.assertEqual(
            self.registry.base_retrieval_profile_id,
            ACCEPTED_RETRIEVAL_PROFILE.digest,
        )
        self.assertNotEqual(self.registry.digest, self.registry.method_profile_id)

    def test_registry_identity_ignores_relationship_list_order(self):
        changed = registry_value()
        changed["relationship_types"] = list(reversed(changed["relationship_types"]))
        self.assertEqual(validate_relationship_registry(changed).digest, self.registry.digest)

    def test_unknown_registry_field_is_rejected(self):
        changed = registry_value()
        changed["model_assisted_discovery"] = True
        self.assert_reason(changed, "RELATIONSHIP_SCHEMA_FIELD_UNKNOWN")

    def test_unqualified_active_type_is_rejected(self):
        changed = registry_value()
        changed["relationship_types"][0]["relationship_type"] = "model_suggested"
        self.assert_reason(changed, "RELATIONSHIP_TYPE_UNQUALIFIED")

    def test_more_than_one_hop_is_rejected(self):
        changed = registry_value()
        changed["traversal"]["maximum_hops"] = 2
        self.assert_reason(changed, "RELATIONSHIP_TRAVERSAL_UNSUPPORTED")

    def test_reference_extraction_reads_only_physical_identifier_text(self):
        self.assertEqual(
            extract_explicit_references(
                "Apply 99 TST 2002, then submit Form no. TST-9001; repeat 99 TST 2002."
            ),
            ("99 TST 2002", "TST-9001"),
        )

    def test_declaration_extraction_does_not_treat_ordinary_reference_as_owner(self):
        self.assertEqual(
            extract_declared_identifiers(
                [
                    "Policy Number: 99 TST 2002. Effective date: 2099-01-01.",
                    "Apply 99 TST 2001.",
                ]
            ),
            ("99 TST 2002",),
        )

    def test_declaration_extraction_reads_multiline_document_control_metadata(self):
        self.assertEqual(
            extract_declared_identifiers(
                [
                    "Organization: Synthetic Example Organization\n"
                    "Document Context: Controlled Materials Access\n"
                    "Policy Number: 99 TST 2001\n"
                    "Department: Operations"
                ]
            ),
            ("99 TST 2001",),
        )

    def test_record_instance_identifier_is_not_a_document_declaration(self):
        self.assertEqual(extract_declared_identifiers(["Request ID: REQ-0001"]), ())

    def test_unambiguous_reference_creates_deterministic_edge(self):
        first = resolve_explicit_references((evidence(),), (self.beta,), self.registry)[0]
        second = resolve_explicit_references((evidence(),), (self.beta,), self.registry)[0]
        self.assertEqual(first.outcome, "accepted")
        self.assertEqual(first.edge, second.edge)
        self.assertEqual(first.edge.target_document_key, "policy.beta")
        self.assertEqual(first.edge.detection_method, "deterministic")

    def test_prepared_reference_resolves_against_reused_active_owner(self):
        document = SimpleNamespace(
            document_key="policy.alpha",
            class_id="policy",
            source_digest=identity("policy.alpha:source"),
            structural_units=(
                SimpleNamespace(ordinal=0, normalized_text="Apply 99 TST 2002."),
            ),
            chunks=(
                SimpleNamespace(
                    ordinal=0,
                    relevant_excerpt="Apply 99 TST 2002.",
                    retrieval_text="Apply 99 TST 2002.",
                    authoritative_component_ordinals=(),
                    structural_unit_ordinals=(0,),
                    page_start=1,
                    page_end=1,
                ),
            ),
        )
        result = discover_prepared_relationships(
            (document,),
            method_profile_id=identity("method"),
            registry=self.registry,
            additional_owners=(self.beta,),
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].outcome, "accepted")
        self.assertEqual(result[0].edge.target_document_key, "policy.beta")

    def test_multiline_header_representatives_declare_owners_but_do_not_anchor_edges(self):
        def document(key, source, declared, body):
            return SimpleNamespace(
                document_key=key,
                class_id="policy",
                source_digest=identity(source),
                structural_units=(
                    SimpleNamespace(ordinal=0, normalized_text="Organization"),
                    SimpleNamespace(ordinal=1, normalized_text=f"Policy Number: {declared}"),
                    SimpleNamespace(ordinal=2, normalized_text=body),
                ),
                chunks=(
                    SimpleNamespace(
                        ordinal=0,
                        relevant_excerpt=(
                            "Organization: Synthetic Example Organization\n"
                            f"Policy Number: {declared}\n"
                            "Department: Operations"
                        ),
                        retrieval_text=f"Document control metadata\n\nPolicy Number: {declared}",
                        authoritative_component_ordinals=(),
                        structural_unit_ordinals=(0, 1),
                        contextual_fields={
                            "projection_properties": {"retrieval_representative": True}
                        },
                        page_start=1,
                        page_end=1,
                    ),
                    SimpleNamespace(
                        ordinal=1,
                        relevant_excerpt=body,
                        retrieval_text=body,
                        authoritative_component_ordinals=(),
                        structural_unit_ordinals=(2,),
                        contextual_fields={},
                        page_start=1,
                        page_end=1,
                    ),
                ),
            )

        alpha = document(
            "policy.alpha", "alpha:source", "99 TST 2001", "Apply 99 TST 2002."
        )
        beta = document(
            "policy.beta", "beta:source", "99 TST 2002", "No external reference."
        )
        result = discover_prepared_relationships(
            (alpha, beta),
            method_profile_id=identity("method"),
            registry=self.registry,
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].outcome, "accepted")
        self.assertEqual(result[0].edge.target_document_key, "policy.beta")

    def test_self_declaration_is_ignored(self):
        item = evidence("99 TST 2001")
        owner = ReferenceOwner("99 TST 2001", "policy.alpha", identity("policy.alpha"))
        result = resolve_explicit_references((item,), (owner,), self.registry)[0]
        self.assertEqual((result.outcome, result.reason_code), ("ignored", "REFERENCE_SELF_DECLARATION"))
        self.assertIsNone(result.edge)

    def test_ambiguous_reference_requires_quarantine(self):
        duplicate = ReferenceOwner("99 TST 2002", "policy.gamma", identity("policy.gamma"))
        result = resolve_explicit_references(
            (evidence(),), (self.beta, duplicate), self.registry
        )[0]
        self.assertTrue(result.requires_quarantine)
        self.assertEqual(result.reason_code, "REFERENCE_TARGET_AMBIGUOUS")

    def test_unknown_corpus_shaped_reference_requires_quarantine(self):
        result = resolve_explicit_references((evidence("99 TST 2999"),), (), self.registry)[0]
        self.assertTrue(result.requires_quarantine)
        self.assertEqual(result.reason_code, "REFERENCE_TARGET_UNRESOLVED")

    def test_audited_external_override_creates_nontraversable_observation(self):
        item = evidence("99 TST 2999")
        override = RelationshipOverride(
            evidence_identity=item.identity,
            audit_identity=identity("audit:1"),
            reason_code="verified_external",
            external_identity="external:99-tst-2999",
        )
        result = resolve_explicit_references(
            (item,), (), self.registry, overrides=(override,)
        )[0]
        self.assertEqual(result.outcome, "external")
        self.assertEqual(result.edge.relationship_type, "explicit_reference.external")
        self.assertEqual(result.edge.override_audit_identity, identity("audit:1"))
        self.assertEqual(result.edge.override_reason_code, "verified_external")
        self.assertFalse(self.registry.by_id()[result.edge.relationship_type].influences_retrieval)

    def test_audited_document_override_must_name_known_catalog_target(self):
        item = evidence("99 TST 2999")
        override = RelationshipOverride(
            evidence_identity=item.identity,
            audit_identity=identity("audit:2"),
            reason_code="operator_resolved",
            target_document_key="policy.beta",
        )
        result = resolve_explicit_references(
            (item,), (self.beta,), self.registry, overrides=(override,)
        )[0]
        self.assertEqual(result.outcome, "accepted")
        self.assertEqual(result.edge.detection_method, "operator_override")
        self.assertEqual(result.edge.override_audit_identity, identity("audit:2"))

    def test_supersedes_edge_targets_fixed_prior_version(self):
        edge = build_supersedes_edge(
            document_identity=identity("policy.alpha"),
            prior_document_version_identity=identity("policy.alpha:v0"),
            source_artifact_set_identity=identity("policy.alpha:artifacts:v1"),
            evidence_citation_identity=identity("policy.alpha:citation:v1"),
            registry=self.registry,
        )
        self.assertEqual((edge.relationship_type, edge.target_kind), ("supersedes", "document_version"))
        self.assertFalse(self.registry.by_id()["supersedes"].influences_retrieval)

    def test_one_hop_traversal_applies_authorization_cycle_and_target_dedup(self):
        a, b, c = identity("a"), identity("b"), identity("c")
        version_b = identity("b:v1")
        edges = (
            TraversalEdge(identity("edge:a-b:1"), "explicit_reference.document", a, b, version_b, identity("cite:1")),
            TraversalEdge(identity("edge:a-b:2"), "explicit_reference.document", a, b, version_b, identity("cite:2")),
            TraversalEdge(identity("edge:b-a"), "explicit_reference.document", b, a, identity("a:v1"), identity("cite:3")),
            TraversalEdge(identity("edge:a-c"), "explicit_reference.document", a, c, identity("c:v1"), identity("cite:4")),
        )
        result = expand_one_hop(
            (a,), edges, allowed_document_identities={a, b}, registry=self.registry
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].target_document_identity, b)
        self.assertEqual(result[0].inclusion_reason, "explicit_reference_one_hop")

    def test_one_hop_keeps_reference_target_already_present_in_direct_seeds(self):
        a, b = identity("a"), identity("b")
        edges = (
            TraversalEdge(
                identity("edge:a-b"),
                "explicit_reference.document",
                a,
                b,
                identity("b:v1"),
                identity("cite:a-b"),
            ),
            TraversalEdge(
                identity("edge:b-a"),
                "explicit_reference.document",
                b,
                a,
                identity("a:v1"),
                identity("cite:b-a"),
            ),
        )
        result = expand_one_hop(
            (a, b), edges, allowed_document_identities={a, b}, registry=self.registry
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].seed_document_identity, a)
        self.assertEqual(result[0].target_document_identity, b)

    def test_duplicate_target_uses_highest_ranked_reference_not_hash_order(self):
        a, b = identity("a"), identity("b")
        lower_ranked = TraversalEdge(
            identity("edge:hash-first"),
            "explicit_reference.document",
            a,
            b,
            identity("b:v1"),
            identity("cite:hash-first"),
        )
        higher_ranked = TraversalEdge(
            identity("edge:responsive"),
            "explicit_reference.document",
            a,
            b,
            identity("b:v1"),
            identity("cite:responsive"),
        )
        result = expand_one_hop(
            (a,),
            (lower_ranked, higher_ranked),
            allowed_document_identities={a, b},
            registry=self.registry,
            relationship_priorities={
                lower_ranked.relationship_id: 9,
                higher_ranked.relationship_id: 1,
            },
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].relationship_id, higher_ranked.relationship_id)


if __name__ == "__main__":
    unittest.main()
