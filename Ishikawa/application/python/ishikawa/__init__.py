"""Ishikawa ingestion and retrieval package.

Import concrete capabilities from their modules. Keeping package import free
of eager optional imports lets database-only tools run without loading the
YAML surface and lets validation-only tools run without loading a DB driver.
"""
