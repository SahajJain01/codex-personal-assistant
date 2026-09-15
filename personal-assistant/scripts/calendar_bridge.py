"""Calendar transport using the installed Hermes Google Workspace authentication.

No credentials or OAuth flow are implemented here. Writes consume prepared journal
operations; a durable dispatch claim prevents replay after an uncertain response.
"""

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import uuid


def load_service(script):
    path = Path(script).resolve(strict=True)
    if path.name != "google_api.py":
        raise ValueError("Select Hermes google-workspace/scripts/google_api.py")
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("hermes_google_workspace", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not callable(getattr(module, "build_service", None)):
        raise RuntimeError("Hermes Google Workspace build_service is unavailable")
    return module.build_service("calendar", "v3")


def pages(method, **params):
    items, seen = [], set()
    while True:
        response = method(**params).execute(num_retries=0)
        items.extend(response.get("items", []))
        token = response.get("nextPageToken")
        if not token:
            return items
        if token in seen:
            raise RuntimeError("Calendar pagination repeated; data is incomplete")
        seen.add(token)
        params["pageToken"] = token


def events(service, calendar, start, end, timezone):
    return pages(
        service.events().list,
        calendarId=calendar,
        timeMin=start,
        timeMax=end,
        timeZone=timezone,
        singleEvents=True,
        showDeleted=False,
        maxResults=2500,
    )


def normalize(event, calendar):
    """Stable editable fields used by the PowerShell ownership fingerprint."""
    reminders = event.get("reminders", {})
    return {
        "id": event["id"],
        "calendarId": calendar,
        "title": event.get("summary", ""),
        "description": event.get("description", ""),
        "start": event["start"].get("dateTime", event["start"].get("date")),
        "end": event["end"].get("dateTime", event["end"].get("date")),
        "visibility": event.get("visibility", "default"),
        "transparency": event.get("transparency", "opaque"),
        "attendees": event.get("attendees", []),
        "recurrence": event.get("recurrence", []),
        "reminders": {
            "use_default": reminders.get("useDefault", True),
            "overrides": reminders.get("overrides", []),
        },
        "meet": event.get("hangoutLink", "") or event.get("conferenceData") or "",
        "eventType": event.get("eventType", "default"),
        "details": {
            key: event.get(key)
            for key in (
                "location",
                "colorId",
                "attachments",
                "extendedProperties",
                "source",
                "guestsCanModify",
                "guestsCanInviteOthers",
                "guestsCanSeeOtherGuests",
                "status",
                "recurringEventId",
                "originalStartTime",
                "locked",
            )
        },
    }


def busy(event):
    return (
        event.get("status") != "cancelled"
        and event.get("transparency", "opaque") != "transparent"
        and not any(
            a.get("self") and a.get("responseStatus") == "declined"
            for a in event.get("attendees", [])
        )
    )


class Store:
    def __init__(self, workspace, token):
        self.workspace = Path(workspace).resolve(strict=True)
        self.token = token

    def call(self, command, request=None):
        args = [
            "powershell",
            "-NoProfile",
            "-NonInteractive",
            "-File",
            str(Path(__file__).with_name("Assistant.ps1")),
            "-Workspace",
            str(self.workspace),
            "-Command",
            command,
        ]
        if self.token:
            args += ["-RunToken", self.token]
        if request is not None:
            folder = self.workspace / "requests"
            folder.mkdir(exist_ok=True)
            path = folder / f"bridge-{uuid.uuid4().hex}.json"
            path.write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
            args += ["-RequestPath", str(path)]
        # Keep requests as private recovery evidence; never print credentials.
        result = subprocess.run(args, capture_output=True, check=False)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace"))
        return json.loads(result.stdout.decode("utf-8-sig"))


def dispatch(service, store, operation_id):
    state = store.call("Read")
    matches = [o for o in state["calendarOperations"] if o["id"] == operation_id]
    if len(matches) != 1 or matches[0]["status"] != "pending":
        raise ValueError(
            "Only a pending operation may dispatch; reconcile other states"
        )
    op = matches[0]
    args = op["connectorArguments"]
    calendar = args["calendar_id"]
    if (
        not state["config"]["calendarWrites"]
        or calendar != state["config"]["writeCalendarId"]
    ):
        raise ValueError("Calendar writes are disabled or target changed")
    endpoint = service.events()
    etag = None
    if op["action"] != "create":
        current = endpoint.get(calendarId=calendar, eventId=args["event_id"]).execute(
            num_retries=0
        )
        if normalize(current, calendar) != op["before"]:
            raise ValueError(
                "User edited the block; preserve it and reconcile an override"
            )
        etag = current.get("etag")
        if not etag:
            raise ValueError("Missing ETag; conditional mutation is unavailable")

    if op["action"] != "delete":
        # Google event-list bounds select overlaps, including all-day instances.
        for calendar_id in dict.fromkeys([*state["config"]["calendarIds"], calendar]):
            for event in events(
                service,
                calendar_id,
                args["start_time"],
                args["end_time"],
                args["timezone_str"],
            ):
                own = (
                    op["action"] == "update"
                    and calendar_id == calendar
                    and event["id"] == args["event_id"]
                )
                if busy(event) and not own:
                    raise ValueError("Fresh calendar conflict; replan before writing")
        body = {
            "summary": args["title"],
            "description": args["description"],
            "start": {"dateTime": args["start_time"], "timeZone": args["timezone_str"]},
            "end": {"dateTime": args["end_time"], "timeZone": args["timezone_str"]},
            "visibility": "private",
            "transparency": "opaque",
            "eventType": "default",
        }
        if op["action"] == "create":
            # Google accepts base32hex IDs. Same operation always has the same ID.
            body.update(
                id="pa" + op["id"],
                attendees=[],
                reminders={"useDefault": False, "overrides": []},
            )
            call = endpoint.insert(calendarId=calendar, body=body, sendUpdates="none")
        else:
            call = endpoint.patch(
                calendarId=calendar,
                eventId=args["event_id"],
                body=body,
                sendUpdates="none",
            )
    else:
        call = endpoint.delete(
            calendarId=calendar, eventId=args["event_id"], sendUpdates="none"
        )
    if etag:
        call.headers["If-Match"] = etag
    # This validates the lease and preparation age and saves uncertain BEFORE send.
    store.call("DispatchCalendar", {"operationId": operation_id})
    response = call.execute(num_retries=0)
    event_id = "pa" + op["id"] if op["action"] == "create" else args["event_id"]
    if op["action"] == "delete":
        try:
            endpoint.get(calendarId=calendar, eventId=event_id).execute(num_retries=0)
        except Exception as error:
            if getattr(getattr(error, "resp", None), "status", None) not in (404, 410):
                raise
        else:
            raise RuntimeError("Deletion not confirmed; operation remains uncertain")
        observed = None
    else:
        if response.get("id") != event_id:
            raise RuntimeError("Unexpected event ID; reconcile before proceeding")
        observed = normalize(
            endpoint.get(calendarId=calendar, eventId=event_id).execute(num_retries=0),
            calendar,
        )
    store.call(
        "CompleteCalendar",
        {
            "operationId": operation_id,
            "outcome": "applied",
            "event": observed,
            "evidence": "Hermes bridge full API readback",
        },
    )
    return {"operationId": operation_id, "status": "applied", "event": observed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--google-script", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("calendars")
    listing = sub.add_parser("events")
    listing.add_argument("--calendar", required=True)
    listing.add_argument("--start", required=True)
    listing.add_argument("--end", required=True)
    listing.add_argument("--timezone", required=True)
    get = sub.add_parser("get")
    get.add_argument("--calendar", required=True)
    get.add_argument("--event", required=True)
    send = sub.add_parser("dispatch")
    send.add_argument("--workspace", required=True)
    send.add_argument("--run-token", required=True)
    send.add_argument("--operation", required=True)
    args = parser.parse_args()
    service = load_service(args.google_script)
    if args.command == "calendars":
        result = pages(service.calendarList().list)
    elif args.command == "events":
        result = events(service, args.calendar, args.start, args.end, args.timezone)
    elif args.command == "get":
        raw = (
            service.events()
            .get(calendarId=args.calendar, eventId=args.event)
            .execute(num_retries=0)
        )
        result = {"raw": raw, "normalized": normalize(raw, args.calendar)}
    else:
        result = dispatch(
            service, Store(args.workspace, args.run_token), args.operation
        )
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
