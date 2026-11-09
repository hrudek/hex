"""Private Unix-local SQLite store and byte-exact raw evidence; no networking."""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import os
import secrets
import sqlite3
import time
from pathlib import Path

from archive import Export, Invalid, canonical, identifier


def outside_checkout(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    for parent in (resolved, *resolved.parents):
        if (parent / ".git").exists():
            raise Invalid("Store must be outside every Git checkout (including linked worktrees)")
    return resolved


def sync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_private(path: Path, data: bytes) -> None:
    temporary = path.with_name(".tmp-" + secrets.token_hex(16))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as target:
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


class Store:
    """Use as a context manager. Operations serialize with a two-second lock timeout."""
    def __init__(self, path: Path, *, create: bool = False):
        self.path = outside_checkout(path)
        self.create = create
        self.connection = None
        self.lock_fd = None
        self.old_umask = None

    def _validate_destination(self):
        if not self.path.exists():
            if self.create:
                return
            raise Invalid("Store directory does not exist; import first")
        if self.path.is_dir() and not any(self.path.iterdir()) and self.create:
            return
        database = self.path / "archive.sqlite3"
        valid = False
        if database.is_file() and not database.is_symlink():
            try:
                with contextlib.closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=2)) as con:
                    valid = (con.execute("PRAGMA user_version").fetchone()[0] == 1
                             and con.execute("SELECT value FROM meta WHERE name='format'").fetchone()
                             == (b"hexplus.dictation-local-store",))
            except sqlite3.Error:
                pass
        if not valid:
            raise Invalid("Store directory exists and is not a Hex+ store; choose a new or empty directory")

    def __enter__(self):
        self.old_umask = os.umask(0o077)
        try:
            self._validate_destination()  # Before chmod, lock creation or opening a writable database.
            if self.create:
                self.path.mkdir(mode=0o700, parents=True, exist_ok=True)
            if not self.path.is_dir():
                raise Invalid("Store directory does not exist; import first")
            self.path.chmod(0o700)
            self.lock_fd = os.open(self.path / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            os.fchmod(self.lock_fd, 0o600)
            deadline = time.monotonic() + 2
            while True:
                try:
                    fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise Invalid("Store busy; retry after the other operation finishes") from None
                    time.sleep(0.02)
            database = self.path / "archive.sqlite3"
            if database.is_symlink():
                raise Invalid("Refusing a symlink database")
            fresh = not database.exists()
            if fresh and not self.create:
                raise Invalid("Store database does not exist; import first")
            self.connection = sqlite3.connect(database, timeout=2)
            database.chmod(0o600)
            if not fresh:
                if self.connection.execute("PRAGMA user_version").fetchone()[0] != 1:
                    raise Invalid("Unsupported local store version; existing data left intact")
                try:
                    marker = self.connection.execute("SELECT value FROM meta WHERE name='format'").fetchone()
                except sqlite3.Error:
                    raise Invalid("Not a Hex+ local store; existing data left intact") from None
                if marker != (b"hexplus.dictation-local-store",):
                    raise Invalid("Not a Hex+ local store; existing data left intact")
            self.connection.execute("PRAGMA synchronous=FULL")
            self.connection.execute("PRAGMA journal_mode=DELETE")
            self.connection.execute("PRAGMA secure_delete=ON")
            if fresh:
                self.connection.executescript("""
                    CREATE TABLE meta (name TEXT PRIMARY KEY, value BLOB NOT NULL);
                    CREATE TABLE imports (digest TEXT PRIMARY KEY, envelope TEXT NOT NULL,
                        warnings TEXT NOT NULL, ids TEXT NOT NULL, sequence INTEGER NOT NULL);
                    CREATE TABLE entries (archive_id TEXT NOT NULL, entry_id TEXT NOT NULL,
                        revision INTEGER NOT NULL, body TEXT NOT NULL, digest TEXT NOT NULL,
                        PRIMARY KEY(archive_id, entry_id));
                    PRAGMA user_version=1;
                """)
                self.connection.execute("INSERT INTO meta VALUES ('format', ?)", (b"hexplus.dictation-local-store",))
                self.connection.execute("INSERT INTO meta VALUES ('hmac_secret', ?)", (secrets.token_bytes(32),))
                self.connection.commit()
                sync_directory(self.path)
            if self.connection.execute("PRAGMA user_version").fetchone()[0] != 1:
                raise Invalid("Unsupported local store version; existing data left intact")
            row = self.connection.execute("SELECT value FROM meta WHERE name='hmac_secret'").fetchone()
            if row is None or not isinstance(row[0], bytes) or len(row[0]) != 32:
                raise Invalid("Invalid local store key; do not recreate over existing data")
            self.secret = row[0]
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_args):
        if self.connection is not None:
            self.connection.close()
            self.connection = None
        if self.lock_fd is not None:
            os.close(self.lock_fd)  # Releases flock, including after an exception.
            self.lock_fd = None
        if self.old_umask is not None:
            os.umask(self.old_umask)
            self.old_umask = None

    def import_export(self, export: Export, *, before_commit=lambda: None) -> dict:
        digest = hashlib.sha256(export.raw).hexdigest()
        archive_id = identifier(export.envelope["archiveID"], "archiveID")
        evidence = self.path / "exports"
        if evidence.is_symlink():
            raise Invalid("Refusing a symlink evidence directory")
        evidence.mkdir(mode=0o700, exist_ok=True)
        evidence.chmod(0o700)
        blob = evidence / (digest + ".json")
        if blob.is_symlink():
            raise Invalid("Refusing a symlink evidence file")
        if not blob.exists():
            atomic_private(blob, export.raw)
        else:
            blob.chmod(0o600)
            checksum = hashlib.sha256()
            with blob.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    checksum.update(chunk)
            if checksum.hexdigest() != digest:
                raise Invalid("Existing raw evidence checksum mismatch; import stopped")
        result = {"inserted": 0, "updated": 0, "unchanged": 0, "older": 0, "conflicts": 0,
                  "skipped": export.source_count - len(export.entries),
                  "warnings": list(export.warnings)}
        con = self.connection
        con.execute("BEGIN IMMEDIATE")
        try:
            for i, entry in enumerate(export.entries):
                entry_id = identifier(entry["id"], "id")
                revision = entry.get("revision", 1)
                body = canonical(entry)
                previous = con.execute("SELECT revision, body FROM entries WHERE archive_id=? AND entry_id=?",
                                       (archive_id, entry_id)).fetchone()
                if previous is not None and revision <= previous[0]:
                    if revision < previous[0]:
                        result["older"] += 1
                    elif body != previous[1]:
                        result["conflicts"] += 1
                        result["warnings"].append(f"entries[{i}]: equal revision conflicts; existing whole entry kept")
                    else:
                        result["unchanged"] += 1
                    continue
                con.execute("INSERT OR REPLACE INTO entries VALUES (?,?,?,?,?)",
                            (archive_id, entry_id, revision, body, digest))
                result["updated" if previous else "inserted"] += 1
            sequence = con.execute("SELECT COALESCE(MAX(sequence),0)+1 FROM imports").fetchone()[0]
            # Reimporting the same bytes does not make an old export the latest observation.
            con.execute("INSERT OR IGNORE INTO imports VALUES (?,?,?,?,?)", (digest, canonical(export.envelope),
                        canonical(result["warnings"]), canonical([identifier(e["id"], "id") for e in export.entries]), sequence))
            before_commit()  # Fault-injection seam for transaction rollback tests.
            con.commit()  # SQLite FULL handles transaction durability (including its journal).
        except BaseException:
            con.rollback()
            raise
        return result

    def records(self):
        import json
        for archive_id, entry_id, body in self.connection.execute("SELECT archive_id, entry_id, body FROM entries ORDER BY archive_id, entry_id"):
            yield archive_id, entry_id, json.loads(body)

    def imports(self):
        import json
        for envelope, warnings, ids in self.connection.execute("SELECT envelope, warnings, ids FROM imports ORDER BY sequence"):
            yield json.loads(envelope), json.loads(warnings), set(json.loads(ids))
