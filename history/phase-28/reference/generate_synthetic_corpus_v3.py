#!/usr/bin/env python3
"""Generate the 30-document Ishikawa synthetic corpus v3.

The generator uses the accepted v1 PDF primitives and preserves the six v2
document identities as semantic anchors.  It creates only fictional content in
an operator-selected output directory.  It never reads or writes the black
corpus and never mutates corpus v1 or v2.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


ORGANIZATION_NAME = "Synthetic Example Organization"
ORGANIZATION_ABBREVIATION = "SEO"
DEPARTMENT_LABELS = ("Department:", "Dept:", "Dept.:")
PAGES_PER_DOCUMENT = 5


# filename, policy number, title, context, department, type, subject,
# controlling action, record identity, decision threshold, related documents
CATALOG_ROWS = (
    ("OPS_17_CTL_2001.pdf", "99 TST 2001", "Controlled Materials Access Policy", "Controlled Materials Access", "Information Technology", "policy", "time-bounded access to controlled training materials", "authorize access only for an approved role and purpose", "controlled access request", "complete evidence and a recorded expiration", ("99 TST 2002", "TST-9001", "99 TST 2006")),
    ("OPS_17_CTL_2002_RevA.pdf", "99 TST 2002", "Controlled Access Exception Review", "Controlled Access Exception Review", "Operations Control", "policy", "review of controlled-access exceptions", "apply the exception decision matrix", "exception decision record", "documented risk, evidence, and compensating controls", ("99 TST 2001", "TST-9001", "99 TST 2022")),
    ("31_SCH_2003.pdf", "99 TST 2003", "Scheduled Activity Policy", "Controlled Activity Scheduling", "Scheduling Office", "policy", "scheduled controlled activity", "coordinate the approved window and operational owner", "activity schedule record", "approved start, end, owner, and readiness evidence", ("99 TST 2001", "99 TST 2011", "TST-9011")),
    ("Form_TST9001.pdf", "TST-9001", "Controlled Access Exception Request", "Controlled Access Exception Request", "Information Technology", "form", "a request for temporary controlled access", "capture requester, scope, risk, dates, and controls", "TST-9001 request", "all required fields and reviewer certification", ("99 TST 2001", "99 TST 2002", "99 TST 2005")),
    ("Governance_Manual_2005_Revision_3.pdf", "99 TST 2005", "Operations Governance Manual", "Governance Records", "Records Governance", "manual", "governance of requests, decisions, evidence, and lifecycle events", "preserve authoritative provenance and record history", "governance record", "complete linkage, retention, correction, and audit data", ("99 TST 2001", "99 TST 2020", "99 TST 2022")),
    ("SOP_42_IR_2006.pdf", "99 TST 2006", "Incident Reporting and Response Procedure", "Incident Reporting and Response", "Information Technology", "procedure", "controlled-materials incidents", "intake, classify, contain, notify, and close the incident", "incident record", "containment plus complete owned closure actions", ("99 TST 2030", "99 TST 2031", "TST-9030")),
    ("CM_Handling_2010.pdf", "99 TST 2010", "Controlled Materials Handling Procedure", "Controlled Materials Handling", "Operations Control", "procedure", "receipt, use, transfer, and return of controlled materials", "maintain custody and reconcile every transfer", "custody log", "matched sender, recipient, time, and disposition", ("99 TST 2001", "99 TST 2002", "99 TST 2006")),
    ("Scheduling_Procedure_2011.pdf", "99 TST 2011", "Controlled Activity Scheduling Procedure", "Activity Scheduling Procedure", "Scheduling Office", "procedure", "creation and modification of controlled schedules", "validate dependencies before publishing a schedule", "schedule work item", "resource, owner, dependency, and approval readiness", ("99 TST 2003", "TST-9011", "99 TST 2013")),
    ("Form_Schedule_Change_9011.pdf", "TST-9011", "Schedule Change Request", "Schedule Change Request", "Scheduling Office", "form", "a requested change to approved controlled activity", "capture impact, reason, affected requests, and approval", "schedule change request", "complete impact and conflict review", ("99 TST 2003", "99 TST 2011", "99 TST 2012")),
    ("After_Hours_Operations_2012.pdf", "99 TST 2012", "After-Hours Operations Policy", "After-Hours Operations", "Operations Control", "policy", "controlled activity outside standard support hours", "require an on-call owner and rollback path", "after-hours authorization", "confirmed coverage, communications, and recovery", ("99 TST 2003", "99 TST 2011", "99 TST 2031")),
    ("Operational_Readiness_2013.pdf", "99 TST 2013", "Operational Readiness Checklist", "Operational Readiness", "Operations Control", "checklist", "readiness for scheduled controlled activity", "verify prerequisites immediately before execution", "readiness checklist", "every mandatory check marked ready or formally waived", ("99 TST 2003", "99 TST 2011", "99 TST 2022")),
    ("Records_Retention_2020.pdf", "99 TST 2020", "Records Retention Policy", "Records Retention", "Records Governance", "policy", "retention and disposition of operational records", "assign retention by authoritative record class", "retention schedule entry", "closed lifecycle plus satisfied hold requirements", ("99 TST 2005", "99 TST 2021", "TST-9020")),
    ("Record_Correction_2021.pdf", "99 TST 2021", "Record Correction Procedure", "Record Correction", "Records Governance", "procedure", "correction of an authoritative operational record", "append a traceable correction without overwriting history", "correction event", "identified source, reason, approver, and superseded value", ("99 TST 2005", "99 TST 2020", "TST-9020")),
    ("Form_Decision_Record_9020.pdf", "TST-9020", "Decision Record Form", "Decision Record", "Records Governance", "form", "recording an operational or policy decision", "capture authority, rationale, evidence, controls, and review date", "decision record", "complete evidence links and accountable approval", ("99 TST 2005", "99 TST 2020", "99 TST 2022")),
    ("Audit_Evidence_Guide_2022.pdf", "99 TST 2022", "Audit Evidence Guide", "Audit Evidence", "Legal and Compliance", "guide", "evidence used to prove policy and procedure execution", "preserve attributable, complete, and reproducible evidence", "audit evidence package", "source identity, custody, time, and governing requirement", ("99 TST 2005", "99 TST 2020", "TST-9020")),
    ("Incident_Classification_2030.pdf", "99 TST 2030", "Incident Classification Policy", "Incident Classification", "Incident Response", "policy", "classification of operational, security, access, and records incidents", "assign type and provisional severity from observed impact", "incident classification", "known impact, affected assets, duration, and control status", ("99 TST 2006", "99 TST 2031", "TST-9030")),
    ("Incident_Escalation_2031.pdf", "99 TST 2031", "Incident Escalation Procedure", "Incident Escalation", "Incident Response", "procedure", "notification and escalation of active incidents", "notify the correct owner within the severity window", "escalation log", "severity, ongoing status, affected records, and missed controls", ("99 TST 2006", "99 TST 2030", "99 TST 2043")),
    ("Form_Incident_Intake_9030.pdf", "TST-9030", "Incident Intake Form", "Incident Intake", "Incident Response", "form", "initial reporting of a suspected incident", "capture reporter, location, department, time, symptoms, and affected records", "incident intake record", "enough facts to assign a provisional type and owner", ("99 TST 2006", "99 TST 2030", "99 TST 2031")),
    ("Post_Incident_Review_2032.pdf", "99 TST 2032", "Post-Incident Review Guide", "Post-Incident Review", "Legal and Compliance", "guide", "review of incident causes, response, and corrective actions", "separate observed facts from conclusions and lessons", "post-incident review", "closed actions with owners, evidence, and due dates", ("99 TST 2006", "99 TST 2022", "99 TST 2031")),
    ("Acceptable_Use_2040.pdf", "99 TST 2040", "Acceptable Use Policy", "Acceptable Use", "Executive Office", "policy", "acceptable use of organizational technology and information", "permit authorized business use and prohibit unsafe or unapproved activity", "acceptable-use acknowledgment", "authorized purpose, approved technology, and protected information", ("99 TST 2041", "99 TST 2042", "99 TST 2043")),
    ("Remote_Access_2041.pdf", "99 TST 2041", "Remote Access Policy", "Remote Access", "Cybersecurity", "policy", "remote connection to organizational systems", "require approved identity, managed endpoints, and monitored sessions", "remote access authorization", "current need, device compliance, and strong authentication", ("99 TST 2040", "TST-9040", "99 TST 2053")),
    ("Mobile_Device_2042.pdf", "99 TST 2042", "Mobile Device Standard", "Mobile Device Use", "Information Technology", "standard", "mobile devices accessing organizational information", "enforce enrollment, encryption, locking, and reporting controls", "device compliance record", "managed state and supported security configuration", ("99 TST 2040", "99 TST 2041", "99 TST 2043")),
    ("Form_Use_Exception_9040.pdf", "TST-9040", "Technology Use Exception Request", "Technology Use Exception", "Cybersecurity", "form", "a temporary exception to technology-use controls", "capture business need, affected control, duration, risk, and compensating safeguards", "use exception request", "time limit, accountable owner, and approved safeguards", ("99 TST 2040", "99 TST 2041", "99 TST 2042")),
    ("Security_Event_Reporting_2043.pdf", "99 TST 2043", "Security Event Reporting Procedure", "Security Event Reporting", "Cybersecurity", "procedure", "suspected misuse, device loss, credential exposure, or unsafe access", "preserve evidence and route the event for classification", "security event report", "timely notice with affected identity, device, data, and activity", ("99 TST 2030", "99 TST 2031", "TST-9030")),
    ("Third_Party_Access_2050.pdf", "99 TST 2050", "Third-Party Access Policy", "Third-Party Access", "Vendor Management", "policy", "access granted to vendors and external service personnel", "bind access to a sponsor, contract purpose, system scope, and end date", "third-party access record", "approved sponsor, due diligence, controls, and expiration", ("99 TST 2051", "TST-9050", "99 TST 2053")),
    ("Personnel_Access_Lifecycle_2051.pdf", "99 TST 2051", "Personnel Access Lifecycle Procedure", "Personnel Access Lifecycle", "Human Resources", "procedure", "onboarding, transfer, leave, and separation access changes", "coordinate identity changes with effective personnel events", "access lifecycle event", "verified person, role, manager, systems, and effective time", ("99 TST 2050", "TST-9050", "99 TST 2053")),
    ("Data_Classification_2052.pdf", "99 TST 2052", "Data Classification Standard", "Data Classification", "Data Stewardship", "standard", "classification and handling of organizational information", "label information and apply controls proportional to sensitivity", "classification decision", "identified owner, business impact, sharing boundary, and retention need", ("99 TST 2005", "99 TST 2040", "99 TST 2050")),
    ("Form_Access_Authorization_9050.pdf", "TST-9050", "Access Authorization Form", "Access Authorization", "Human Resources", "form", "authorization of workforce or third-party system access", "capture identity, sponsor, role, systems, dates, and approvals", "access authorization", "least privilege plus complete owner and expiration data", ("99 TST 2050", "99 TST 2051", "99 TST 2053")),
    ("Privileged_Access_Review_2053.pdf", "99 TST 2053", "Privileged Access Review Procedure", "Privileged Access Review", "Cybersecurity", "procedure", "periodic review of elevated access", "reconcile approved need against observed privileged accounts", "privileged access review", "current owner, justified role, recent use, and remediation status", ("99 TST 2041", "99 TST 2050", "TST-9050")),
    ("Information_Sharing_2054.pdf", "99 TST 2054", "Information Sharing Policy", "Information Sharing", "Data Stewardship", "policy", "internal and external sharing of classified information", "confirm recipient, purpose, authority, and transfer protection", "information sharing decision", "classification-compatible recipient and transmission control", ("99 TST 2052", "99 TST 2050", "99 TST 2022")),
)


V2_ANCHORS = {
    "OPS_17_CTL_2001.pdf", "OPS_17_CTL_2002_RevA.pdf", "31_SCH_2003.pdf",
    "Form_TST9001.pdf", "Governance_Manual_2005_Revision_3.pdf", "SOP_42_IR_2006.pdf",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_module(path: Path, name: str):
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"{name}_missing_or_unsafe")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"{name}_import_failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _metadata(index: int, row: tuple[Any, ...]) -> dict[str, Any]:
    filename, policy_number, title, context, department, document_type, subject, action, record, threshold, references = row
    month = ((index - 1) % 12) + 1
    review_month = ((month + 5 - 1) % 12) + 1
    return {
        "filename": filename,
        "doc_id": f"SYN-V3-{index:03d}",
        "policy_number": policy_number,
        "title": title,
        "document_context": context,
        "organization_name": ORGANIZATION_NAME,
        "organization_abbreviation": ORGANIZATION_ABBREVIATION,
        "effective_date": f"2099-{month:02d}-01",
        "review_date": f"2099-{review_month:02d}-15",
        "applicability_class": f"Synthetic {document_type.title()}",
        "department_label": DEPARTMENT_LABELS[(index - 1) % len(DEPARTMENT_LABELS)],
        "department": department,
        "approval": f"Synthetic Approval Authority {((index - 1) % 10) + 1}",
        "document_type": document_type,
        "subject": subject,
        "action": action,
        "record": record,
        "threshold": threshold,
        "references": list(references),
        "v2_anchor": filename in V2_ANCHORS,
        "pages": PAGES_PER_DOCUMENT,
        "control_code": f"CTL-{index:03d}",
    }


DOCUMENTS = tuple(_metadata(index, row) for index, row in enumerate(CATALOG_ROWS, start=1))


def _masthead_commands(base: Any, item: dict[str, Any]) -> list[str]:
    left, right, middle = 54.0, 558.0, 306.0
    top, row_height = 604.0, 24.0
    commands = [
        "q 0.82 g 54.0 622.0 94.0 94.0 re f Q",
        base.text_command(item["organization_name"], 421.0, 758.0, 8, "F1"),
        base.line_command(54.0, 736.0, 558.0, 736.0, 0.6),
        base.text_command(item["document_context"], 190.0, 667.0, 19, "F2"),
    ]
    for row in range(4):
        y = top - row * row_height
        commands.append(base.line_command(left, y, right, y, 0.6))
    for x in (left, middle, right):
        commands.append(base.line_command(x, top, x, top - 3 * row_height, 0.6))
    rows = (
        (("Effective Date:", item["effective_date"]), ("Policy Number:", item["policy_number"])),
        (("Applicability/Class:", item["applicability_class"]), (item["department_label"], item["department"])),
        (("Date of Review:", item["review_date"]), ("Approval:", item["approval"])),
    )
    for row_index, row in enumerate(rows):
        y = top - 15.0 - row_index * row_height
        for cell_index, (label, value) in enumerate(row):
            x = left + 7.0 + cell_index * (middle - left)
            commands.append(base.text_command(label, x, y, 8, "F2"))
            commands.append(base.text_command(value, x + (112.0 if cell_index == 0 else 76.0), y, 8, "F1"))
    return commands


def _footer_commands(base: Any, item: dict[str, Any], page: int) -> list[str]:
    return [
        base.line_command(54.0, 72.0, 558.0, 72.0, 0.6),
        base.text_command(f"{item['organization_abbreviation']} Policy", 54.0, 52.0, 8, "F1"),
        base.text_command(item["policy_number"], 116.0, 52.0, 8, "F2"),
        base.text_command(f"Page {page} of {PAGES_PER_DOCUMENT}", 278.0, 44.0, 9, "F1"),
        base.text_command(f"For {item['organization_abbreviation']} Use Only", 445.0, 52.0, 8, "F1"),
        base.text_command(f"{item['effective_date']}; {item['review_date']}", 445.0, 37.0, 7, "F1"),
    ]


def _section_plan(item: dict[str, Any]) -> tuple[tuple[str, tuple[str, ...]], ...]:
    related = item["references"]
    common = (
        ("I. Purpose and Scope", (
            f"{item['title']} governs {item['subject']} for {item['department']} and authorized supporting roles.",
            f"The required control is to {item['action']}. This document does not authorize activity outside its stated scope.",
            f"Control identifier {item['control_code']} distinguishes this requirement from similar controls in related documents.",
        )),
        ("II. Definitions and Responsibilities", (
            f"Accountable Owner means the role responsible for the {item['record']} and the final disposition of its open actions.",
            f"Complete Evidence means evidence sufficient to demonstrate {item['threshold']}.",
            f"The originating operator supplies facts; the {item['department']} reviewer verifies scope, authority, and conflicts.",
            f"Related terms may also appear in {related[0]} and {related[1]}, but each document retains its own decision boundary.",
        )),
        ("III. Required Controls", (
            f"1. Create the {item['record']}. 2. Identify the accountable owner. 3. Record the governing purpose and affected scope.",
            f"4. Verify {item['threshold']}. 5. Record exceptions and their expiration. 6. Preserve evidence of the decision.",
            f"A control is incomplete when its owner, time boundary, authoritative reference, or required evidence is missing.",
            f"The reviewer must distinguish this control from the related but non-equivalent requirements in {related[2]}.",
        )),
        ("IV. Procedure and Exceptions", (
            f"1. Intake the request or event. 2. Validate identity and applicability. 3. Apply {item['control_code']}. 4. Record the outcome.",
            "If facts are ambiguous, request the missing operational fact instead of guessing a department, incident type, or authority.",
            f"An exception is time bounded, identifies compensating controls, and links to both {related[0]} and {related[1]} when applicable.",
            "Urgency does not remove evidence, logging, notification, or later review requirements.",
        )),
        ("V. Records, References, and Review", (
            f"The authoritative output is the {item['record']}; preserve its identifier, owner, timestamps, evidence, approval, and disposition.",
            f"References: {related[0]}; {related[1]}; {related[2]}.",
            f"Review this document on {item['review_date']} or after a material control failure, whichever occurs first.",
            "Corrections append a new traceable version and never silently overwrite prior provenance.",
        )),
    )
    if item["document_type"] in {"form", "checklist"}:
        return (
            ("I. Instructions and Record Identity", common[0][1]),
            ("II. Requester, Scope, and Dates", common[1][1]),
            ("III. Risk and Control Selection", common[2][1]),
            ("IV. Review Decision and Exceptions", common[3][1]),
            ("V. Certification, References, and Retention", common[4][1]),
        )
    return common


def _table_commands(base: Any, item: dict[str, Any]) -> list[str]:
    if item["document_type"] not in {"form", "checklist"}:
        return []
    x_positions = (54.0, 190.0, 330.0, 450.0, 558.0)
    top, row_height = 306.0, 38.0
    commands: list[str] = []
    for row in range(5):
        commands.append(base.line_command(54.0, top - row * row_height, 558.0, top - row * row_height, 0.5))
    for x in x_positions:
        commands.append(base.line_command(x, top, x, top - 4 * row_height, 0.5))
    headers = ("Field", "Value", "Required", "Status")
    rows = (
        ("Record", item["record"][:20], "Yes", "Entered"),
        ("Owner", item["department"][:20], "Yes", "Verified"),
        ("Control", item["control_code"], "Yes", "Reviewed"),
    )
    for column, value in enumerate(headers):
        commands.append(base.text_command(value, x_positions[column] + 5, top - 16, 8, "F2"))
    for row_index, row in enumerate(rows, start=1):
        for column, value in enumerate(row):
            commands.append(base.text_command(value, x_positions[column] + 5, top - row_index * row_height - 16, 7, "F1"))
    return commands


def _page_commands(base: Any, item: dict[str, Any], page: int, heading: str, paragraphs: tuple[str, ...]) -> list[str]:
    commands: list[str] = []
    if page == 1:
        commands.extend(_masthead_commands(base, item))
        heading_y, body_y = 505.0, 477.0
    else:
        commands.extend((
            base.text_command(item["policy_number"], 54.0, 748.0, 8, "F2"),
            base.text_command(item["title"], 150.0, 748.0, 8, "F1"),
            base.line_command(54.0, 735.0, 558.0, 735.0, 0.5),
        ))
        heading_y, body_y = 705.0, 675.0
    commands.append(base.text_command(heading, 54.0, heading_y, 13, "F2"))
    y = body_y
    for paragraph in paragraphs:
        y = base.wrapped_text(commands, paragraph, 54.0, y, width=82, size=9, leading=12, font="F1")
        y -= 8
    if page == 3:
        commands.extend(_table_commands(base, item))
    commands.extend(_footer_commands(base, item, page))
    return commands


def _write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--v1-generator", required=True)
    parser.add_argument("--v2-generator", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()

    output_root = Path(args.output_root).resolve()
    if output_root.exists() or output_root.is_symlink():
        raise SystemExit("output_root_already_exists")
    source_root = output_root / "source"
    evaluation_root = output_root / "evaluation"
    source_root.mkdir(parents=True, mode=0o700)
    evaluation_root.mkdir(mode=0o700)

    v1_path = Path(args.v1_generator).resolve()
    v2_path = Path(args.v2_generator).resolve()
    base = _load_module(v1_path, "ishikawa_synthetic_corpus_v1")
    v2 = _load_module(v2_path, "ishikawa_synthetic_corpus_v2")
    if len(DOCUMENTS) != 30 or len({item["filename"] for item in DOCUMENTS}) != 30:
        raise SystemExit("v3_document_inventory_invalid")
    v2_by_filename = v2.DOCUMENTS
    for item in DOCUMENTS:
        if not item["v2_anchor"]:
            continue
        prior = v2_by_filename.get(item["filename"])
        if prior is None or prior["policy_number"] != item["policy_number"] or prior["document_context"] != item["document_context"] or prior["department"] != item["department"]:
            raise SystemExit("v2_anchor_contract_changed")

    policy_to_document = {item["policy_number"]: item for item in DOCUMENTS}
    if len(policy_to_document) != len(DOCUMENTS):
        raise SystemExit("v3_policy_number_not_unique")
    relationships: list[dict[str, str]] = []
    for item in DOCUMENTS:
        sections = _section_plan(item)
        if len(sections) != PAGES_PER_DOCUMENT:
            raise SystemExit("v3_page_plan_invalid")
        pages = [
            _page_commands(base, item, page, heading, paragraphs)
            for page, (heading, paragraphs) in enumerate(sections, start=1)
        ]
        base.write_pdf(source_root / item["filename"], item["title"], pages)
        for reference in item["references"]:
            target = policy_to_document.get(reference)
            if target is None:
                raise SystemExit("v3_relationship_target_missing")
            relationships.append({
                "source_doc_id": item["doc_id"],
                "source_policy_number": item["policy_number"],
                "target_doc_id": target["doc_id"],
                "target_policy_number": target["policy_number"],
                "relation": "explicit_reference",
            })

    source_manifest = {
        "schema_version": 1,
        "fixture_status": "fully_synthetic_no_source_text",
        "files": [
            {
                "bytes": (source_root / item["filename"]).stat().st_size,
                "doc_id": item["doc_id"],
                "filename": item["filename"],
                "sha256": _sha256(source_root / item["filename"]),
            }
            for item in DOCUMENTS
        ],
    }
    truth = {
        "schema_version": 3,
        "fixture_status": "fully_synthetic_no_source_text",
        "corpus_identity": "synthetic-corpus-v3",
        "accepted_v1_mutated": False,
        "accepted_v2_mutated": False,
        "organization_name": ORGANIZATION_NAME,
        "organization_abbreviation": ORGANIZATION_ABBREVIATION,
        "document_count": len(DOCUMENTS),
        "page_count": len(DOCUMENTS) * PAGES_PER_DOCUMENT,
        "header_contract": {
            "scope": "first_page_only",
            "fields": ["Effective Date", "Policy Number", "Applicability/Class", "Department", "Date of Review", "Approval"],
            "department_label_variants": list(DEPARTMENT_LABELS),
            "non_text_logo": True,
        },
        "footer_contract": {
            "scope": "every_page",
            "left_organization_abbreviation": ORGANIZATION_ABBREVIATION,
            "policy_number_from_document": True,
            "center_page_pattern": "Page N of M",
            "right_organization_abbreviation": ORGANIZATION_ABBREVIATION,
            "semantic_retrieval": False,
        },
        "documents": list(DOCUMENTS),
        "relationships": relationships,
    }
    _write_json(output_root / "source_manifest.json", source_manifest)
    _write_json(evaluation_root / "corpus_truth.json", truth)
    (output_root / "README.md").write_text(
        "# Synthetic Corpus V3\n\n"
        "Thirty fictional documents derived from the accepted corpus-v2 layout. "
        "No source-corpus text or real organization data is present. Evaluation "
        "truth is never an ingestion input.\n",
        encoding="utf-8",
    )
    files = [path for path in sorted(output_root.rglob("*")) if path.is_file() and path.name != "manifest.json"]
    manifest = {
        "schema_version": 3,
        "status": "synthetic_corpus_v3_candidate",
        "source_corpus_content_used": False,
        "accepted_v1_mutated": False,
        "accepted_v2_mutated": False,
        "based_on_v1_generator_sha256": _sha256(v1_path),
        "based_on_v2_generator_sha256": _sha256(v2_path),
        "document_count": len(DOCUMENTS),
        "page_count": len(DOCUMENTS) * PAGES_PER_DOCUMENT,
        "v2_anchor_document_count": sum(1 for item in DOCUMENTS if item["v2_anchor"]),
        "new_document_count": sum(1 for item in DOCUMENTS if not item["v2_anchor"]),
        "department_count": len({item["department"] for item in DOCUMENTS}),
        "relationship_count": len(relationships),
        "files": [
            {"path": path.relative_to(output_root).as_posix(), "bytes": path.stat().st_size, "sha256": _sha256(path)}
            for path in files
        ],
    }
    _write_json(output_root / "manifest.json", manifest)
    print(
        "synthetic_corpus_v3_generation=pass;"
        f"documents={manifest['document_count']};pages={manifest['page_count']};"
        f"v2_anchors={manifest['v2_anchor_document_count']};new_documents={manifest['new_document_count']};"
        f"departments={manifest['department_count']};relationships={manifest['relationship_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
