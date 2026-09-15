"""Transport tests: fake Google responses, no authentication or network."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "bridge",
    Path(__file__).parents[1] / "personal-assistant/scripts/calendar_bridge.py",
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class Request:
    def __init__(self, result, effect=None):
        self.result = result
        self.effect = effect
        self.headers = {}

    def execute(self, num_retries):
        assert num_retries == 0
        if self.effect:
            self.effect()
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


class Google:
    def __init__(self):
        self.overlaps = []
        self.saved = None
        self.writes = []
        self.failure = None

    def events(self):
        return self

    def list(self, **_):
        return Request({"items": self.overlaps})

    def get(self, **_):
        if self.saved is None:
            error = RuntimeError("Not found")
            error.resp = type("Response", (), {"status": 404})()
            return Request(error)
        return Request(self.saved)

    def insert(self, **kwargs):
        def save():
            self.writes.append(kwargs)
            self.saved = {**kwargs["body"], "etag": '"v1"'}

        return Request(self.failure or kwargs["body"], save)

    def patch(self, **kwargs):
        result = {**self.saved, **kwargs["body"]}

        def save():
            self.writes.append(kwargs)
            self.saved = result

        self.last_patch = Request(self.failure or result, save)
        return self.last_patch

    def delete(self, **kwargs):
        def remove():
            self.writes.append(kwargs)
            self.saved = None

        self.last_delete = Request({}, remove)
        return self.last_delete


class Store:
    def __init__(self):
        self.op = {
            "id": "1" * 32,
            "action": "create",
            "status": "pending",
            "before": None,
            "connectorArguments": {
                "calendar_id": "test",
                "title": "Action",
                "description": "marker",
                "start_time": "2026-09-15T12:00:00+07:00",
                "end_time": "2026-09-15T12:30:00+07:00",
                "timezone_str": "Asia/Bangkok",
            },
        }
        self.state = {
            "config": {
                "calendarWrites": True,
                "writeCalendarId": "test",
                "calendarIds": ["test", "other"],
            },
            "calendarOperations": [self.op],
        }
        self.claims = 0

    def call(self, command, request=None):
        if command == "Read":
            return copy.deepcopy(self.state)
        if command == "DispatchCalendar":
            assert self.op["status"] == "pending"
            self.claims += 1
            self.op["status"] = "uncertain"
        if command == "CompleteCalendar":
            self.op["status"] = request["outcome"]
            self.observed = request["event"]


class CalendarTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "win32", "PowerShell runtime is Windows-only")
    def test_real_store_round_trips_unicode_and_enforces_lease(self):
        workspace = Path(tempfile.mkdtemp(prefix="assistant-bridge-store-"))
        config = json.loads(
            (
                Path(__file__).parents[1]
                / "personal-assistant/assets/config.example.json"
            ).read_text()
        )
        config.update(todoPaths=[], screenshotFolders=[], calendarWrites=False)
        store = bridge.Store(workspace, None)
        context = "# Context\n\nไทย — café 📅"
        store.call("Init", {"config": config, "context": context})
        self.assertEqual(store.call("Read")["context"], context)
        state = store.call("Begin")
        with self.assertRaises(RuntimeError):
            store.call("Renew")
        store.token = state["activeRun"]["token"]
        store.call("End")

    def test_full_pagination_and_repeated_token_failure(self):
        calls = []

        def listing(**kwargs):
            calls.append(kwargs)
            return Request(
                {
                    "items": [{"id": len(calls)}],
                    **({"nextPageToken": "next"} if len(calls) == 1 else {}),
                }
            )

        self.assertEqual(len(bridge.pages(listing)), 2)
        self.assertEqual(calls[1]["pageToken"], "next")
        with self.assertRaisesRegex(RuntimeError, "pagination"):
            bridge.pages(lambda **_: Request({"nextPageToken": "same"}))

    def test_busy_semantics(self):
        for event in (
            {"status": "cancelled"},
            {"transparency": "transparent"},
            {"attendees": [{"self": True, "responseStatus": "declined"}]},
        ):
            self.assertFalse(bridge.busy(event))
        self.assertTrue(bridge.busy({"start": {"date": "2026-09-15"}}))

    def test_create_private_deterministic_and_cannot_replay(self):
        google, store = Google(), Store()
        result = bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(result["status"], "applied")
        body = google.writes[0]["body"]
        self.assertEqual(body["id"], "pa" + "1" * 32)
        self.assertEqual(body["visibility"], "private")
        self.assertEqual(body["attendees"], [])
        self.assertNotIn("conferenceData", body)
        self.assertEqual(store.observed["meet"], "")
        with self.assertRaises(ValueError):
            bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(len(google.writes), 1)

    def test_response_lost_is_uncertain_and_not_retried(self):
        google, store = Google(), Store()
        google.failure = TimeoutError("Response lost after server commit")
        with self.assertRaises(TimeoutError):
            bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(store.op["status"], "uncertain")
        with self.assertRaises(ValueError):
            bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(len(google.writes), 1)

    def test_fresh_conflict_prevents_dispatch(self):
        google, store = Google(), Store()
        google.overlaps = [{"id": "appointment", "start": {"date": "2026-09-15"}}]
        with self.assertRaisesRegex(ValueError, "conflict"):
            bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(store.claims, 0)
        self.assertEqual(google.writes, [])

    def prepare_update(self):
        google, store = Google(), Store()
        bridge.dispatch(google, store, store.op["id"])
        store.op.update(action="update", status="pending", before=store.observed)
        store.op["connectorArguments"]["event_id"] = google.saved["id"]
        return google, store

    def test_conditional_update_and_delete(self):
        google, store = self.prepare_update()
        store.op["connectorArguments"]["title"] = "New title"
        bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(google.last_patch.headers["If-Match"], '"v1"')
        store.op.update(action="delete", status="pending", before=store.observed)
        bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(google.last_delete.headers["If-Match"], '"v1"')
        self.assertIsNone(store.observed)

    def test_user_edit_or_missing_etag_prevents_mutation(self):
        for field, value in (("summary", "User changed it"), ("etag", None)):
            google, store = self.prepare_update()
            google.saved[field] = value
            with self.assertRaises(ValueError):
                bridge.dispatch(google, store, store.op["id"])
            self.assertEqual(len(google.writes), 1)

    def test_412_does_not_retry_or_claim_success(self):
        google, store = self.prepare_update()
        google.failure = RuntimeError("412 Precondition Failed")
        with self.assertRaisesRegex(RuntimeError, "412"):
            bridge.dispatch(google, store, store.op["id"])
        self.assertEqual(store.op["status"], "uncertain")
        self.assertEqual(len(google.writes), 2)


if __name__ == "__main__":
    unittest.main()
