#!/usr/bin/env python3

import json
import os
import sys
import time
from base64 import b64encode
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen


REQUIRED_ENV = (
    "COUCHDB_URL",
    "DATABASE",
    "ADMIN_USERNAME",
    "ADMIN_PASSWORD",
    "APP_USERNAME",
    "APP_PASSWORD",
)


@dataclass(frozen=True)
class Config:
    couchdb_url: str
    database: str
    admin_username: str
    admin_password: str
    app_username: str
    app_password: str


class RequestError(Exception):
    def __init__(self, status: int, body: str) -> None:
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


def load_config() -> Config:
    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"missing required environment variables: {', '.join(missing)}")

    return Config(
        couchdb_url=os.environ["COUCHDB_URL"].rstrip("/") + "/",
        database=os.environ["DATABASE"],
        admin_username=os.environ["ADMIN_USERNAME"],
        admin_password=os.environ["ADMIN_PASSWORD"],
        app_username=os.environ["APP_USERNAME"],
        app_password=os.environ["APP_PASSWORD"],
    )


def auth_header(username: str, password: str) -> str:
    token = b64encode(f"{username}:{password}".encode()).decode()
    return f"Basic {token}"


def request(
    config: Config,
    method: str,
    path: str,
    *,
    username: str,
    password: str,
    payload: dict[str, Any] | None = None,
) -> Any:
    data = None
    headers = {"Authorization": auth_header(username, password)}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"

    req = Request(
        urljoin(config.couchdb_url, path.lstrip("/")),
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urlopen(req, timeout=10) as response:
            body = response.read().decode()
            if not body:
                return None
            return json.loads(body)
    except HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RequestError(exc.code, body) from exc
    except URLError as exc:
        raise RuntimeError(str(exc)) from exc


def admin_request(config: Config, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
    return request(
        config,
        method,
        path,
        username=config.admin_username,
        password=config.admin_password,
        payload=payload,
    )


def app_request(config: Config, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
    return request(
        config,
        method,
        path,
        username=config.app_username,
        password=config.app_password,
        payload=payload,
    )


def wait_for_couchdb(config: Config) -> None:
    deadline = time.monotonic() + 300
    last_error = ""

    while time.monotonic() < deadline:
        try:
            admin_request(config, "GET", "/_up")
            print("CouchDB is reachable")
            return
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(5)

    raise RuntimeError(f"CouchDB did not become reachable: {last_error}")


def ensure_database(config: Config) -> None:
    db_path = quote(config.database, safe="")
    try:
        admin_request(config, "PUT", f"/{db_path}")
        print(f"Created database {config.database}")
    except RequestError as exc:
        if exc.status == 412:
            print(f"Database {config.database} already exists")
            return
        raise


def user_doc_id(username: str) -> str:
    return f"org.couchdb.user:{username}"


def app_credentials_are_valid(config: Config) -> bool:
    try:
        session = app_request(config, "GET", "/_session")
    except RequestError as exc:
        if exc.status in (401, 403):
            return False
        raise

    return session.get("userCtx", {}).get("name") == config.app_username


def get_user_doc(config: Config) -> dict[str, Any] | None:
    doc_id = user_doc_id(config.app_username)
    try:
        return admin_request(config, "GET", f"/_users/{quote(doc_id, safe='')}")
    except RequestError as exc:
        if exc.status == 404:
            return None
        raise


def put_user_doc(config: Config, existing_doc: dict[str, Any] | None) -> None:
    doc_id = user_doc_id(config.app_username)
    doc: dict[str, Any] = {
        "_id": doc_id,
        "type": "user",
        "name": config.app_username,
        "roles": existing_doc.get("roles", []) if existing_doc else [],
        "password": config.app_password,
    }
    if existing_doc and "_rev" in existing_doc:
        doc["_rev"] = existing_doc["_rev"]

    admin_request(config, "PUT", f"/_users/{quote(doc_id, safe='')}", doc)


def ensure_app_user(config: Config) -> None:
    if app_credentials_are_valid(config):
        print(f"User {config.app_username} credentials are current")
        return

    for attempt in range(1, 4):
        try:
            existing_doc = get_user_doc(config)
            put_user_doc(config, existing_doc)
            action = "Updated" if existing_doc else "Created"
            print(f"{action} user {config.app_username}")
            return
        except RequestError as exc:
            if exc.status == 409 and attempt < 3:
                time.sleep(1)
                continue
            raise


def ensure_security(config: Config) -> None:
    db_path = quote(config.database, safe="")
    desired_security = {
        "admins": {"names": [], "roles": []},
        "members": {"names": [config.app_username], "roles": []},
    }

    try:
        current_security = admin_request(config, "GET", f"/{db_path}/_security")
    except RequestError as exc:
        if exc.status != 404:
            raise
        current_security = {}

    if current_security == desired_security:
        print(f"Security for database {config.database} is current")
        return

    admin_request(config, "PUT", f"/{db_path}/_security", desired_security)
    print(f"Updated security for database {config.database}")


def verify_app_access(config: Config) -> None:
    db_path = quote(config.database, safe="")
    app_request(config, "GET", f"/{db_path}")
    print(f"Verified user {config.app_username} can access database {config.database}")


def main() -> int:
    try:
        config = load_config()
        wait_for_couchdb(config)
        ensure_database(config)
        ensure_app_user(config)
        ensure_security(config)
        verify_app_access(config)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print("CouchDB provisioning complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
