"""Copy a file or folder to Google Drive with the restored Colab CLI login.

The login in the OS keyring is the one scripts/bootstrap.sh restores from
COLAB_OAUTH_TOKEN_B64. Its `drive.file` scope lets this script create files and read
back the ones it created, with no browser and no per-session consent. It never prints
the token, and it cannot see the rest of the Drive.

Run it through scripts/drive-save.sh, or with the Colab CLI's Python (the only interpreter
here with google-auth and keyring installed):

  scripts/drive_save.py <local path> --dest "Colab Studio/outputs/<date>/<session>" \
      [--quota-project <project id>] [--verify]

The Drive API refuses this login without a quota project (Google's message: "the
drive.googleapis.com API requires a quota project"). Set one with --quota-project, or
DRIVE_QUOTA_PROJECT / GOOGLE_CLOUD_PROJECT in the environment.

Prints one line per file and the destination folder link on stdout.
"""

import argparse
import hashlib
import json
import mimetypes
import os
import sys
import uuid

import keyring
import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

API = "https://www.googleapis.com/drive/v3"
UPLOAD = "https://www.googleapis.com/upload/drive/v3"
FOLDER = "application/vnd.google-apps.folder"
_PROJECT = ""


QUOTA_HELP = (
    "The Drive API needs a Google Cloud project to bill its quota to:\n"
    "  1. Create a project at https://console.cloud.google.com/projectcreate (no billing needed)\n"
    "  2. Enable the Drive API for it at https://console.cloud.google.com/apis/library/drive.googleapis.com\n"
    "  3. Put its id in DRIVE_QUOTA_PROJECT in config/account.env"
)


def _http(quota_project: str = "") -> requests.Session:
    global _PROJECT
    _PROJECT = quota_project
    raw = keyring.get_password("google-colab-cli", "oauth_token")
    if not raw:
        sys.exit("drive_save: no Colab login in the keyring; run scripts/bootstrap.sh or scripts/login.sh")
    creds = Credentials.from_authorized_user_info(json.loads(raw))
    # Always refresh: the stored access token may be expired even when the refresh token is fine.
    if creds.refresh_token:
        creds.refresh(Request())
    if not creds.token:
        sys.exit("drive_save: could not refresh the Colab login; run scripts/login.sh")
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {creds.token}"
    if quota_project:
        s.headers["x-goog-user-project"] = quota_project
    return s


def _check(r: requests.Response) -> None:
    """Turn the Drive-specific refusals into something a reader can act on."""
    if r.status_code == 403 and "quota project" in r.text:
        sys.exit("drive_save: Drive refused the request: no quota project.\n  " + QUOTA_HELP)
    if "USER_PROJECT_DENIED" in r.text or "not found or deleted" in r.text:
        sys.exit(f"drive_save: quota project '{_PROJECT}' is not usable.\n  " + QUOTA_HELP)
    if r.status_code == 403 and "insufficient" in r.text.lower():
        sys.exit("drive_save: the login lacks the drive.file scope; run scripts/login.sh again.")
    if r.status_code >= 400:
        sys.exit(f"drive_save: Drive returned HTTP {r.status_code}: {r.text[:300]}")


def _find(s, name: str, parent: str, folder: bool = False):
    q = f"name = '{name}' and trashed = false"
    if folder:
        q += f" and mimeType = '{FOLDER}'"
    if parent:
        q += f" and '{parent}' in parents"
    r = s.get(f"{API}/files", params={"q": q, "fields": "files(id,name,mimeType)"}, timeout=(10, 60))
    _check(r)
    for f in r.json().get("files", []):
        return f["id"]
    return None


def _folder(s, name: str, parent: str) -> str:
    found = _find(s, name, parent, folder=True)
    if found:
        return found
    meta = {"name": name, "mimeType": FOLDER}
    if parent:
        meta["parents"] = [parent]
    r = s.post(f"{API}/files", params={"fields": "id"}, json=meta, timeout=(10, 60))
    _check(r)
    return r.json()["id"]


def _folder_path(s, path: str) -> str:
    parent = ""
    for part in [p for p in path.split("/") if p]:
        parent = _folder(s, part, parent)
    return parent


def _upload(s, parent: str, local: str) -> dict:
    name = os.path.basename(local)
    mime = mimetypes.guess_type(local)[0] or "application/octet-stream"
    with open(local, "rb") as f:
        data = f.read()
    existing = _find(s, name, parent)
    if existing:
        r = s.patch(
            f"{UPLOAD}/files/{existing}",
            params={"uploadType": "media", "fields": "id,name,size,webViewLink"},
            data=data,
            headers={"Content-Type": mime},
            timeout=(10, 600),
        )
    else:
        boundary = "colab-studio-" + uuid.uuid4().hex
        body = (
            f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode()
            + json.dumps({"name": name, "parents": [parent]}).encode()
            + f"\r\n--{boundary}\r\nContent-Type: {mime}\r\n\r\n".encode()
            + data
            + f"\r\n--{boundary}--\r\n".encode()
        )
        r = s.post(
            f"{UPLOAD}/files",
            params={"uploadType": "multipart", "fields": "id,name,size,webViewLink"},
            data=body,
            headers={"Content-Type": f"multipart/related; boundary={boundary}"},
            timeout=(10, 600),
        )
    _check(r)
    return r.json()


def _read_back(s, file_id: str) -> bytes:
    r = s.get(f"{API}/files/{file_id}", params={"alt": "media"}, timeout=(10, 600))
    _check(r)
    return r.content


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("local", help="file or folder to upload")
    ap.add_argument("--dest", required=True, help='Drive folder path, e.g. "Colab Studio/outputs/2026-11-23/h3"')
    ap.add_argument("--quota-project", default=os.environ.get("DRIVE_QUOTA_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT", ""),
                    help="Google Cloud project id the Drive API bills quota to (required by Google)")
    ap.add_argument("--verify", action="store_true", help="read every file back and compare its sha256")
    args = ap.parse_args()

    if not os.path.exists(args.local):
        sys.exit(f"drive_save: {args.local} does not exist")
    files = []
    if os.path.isdir(args.local):
        for root, _, names in os.walk(args.local):
            for n in sorted(names):
                files.append(os.path.join(root, n))
    else:
        files.append(args.local)
    if not files:
        sys.exit(f"drive_save: no files under {args.local}")

    s = _http(args.quota_project)
    if not args.quota_project:
        print("drive_save: no quota project set; the Drive API will refuse this login.\n  " + QUOTA_HELP,
              file=sys.stderr)
    parent = _folder_path(s, args.dest)
    print(f"folder: https://drive.google.com/drive/folders/{parent}")
    failures = 0
    for path in files:
        rel = os.path.relpath(path, args.local if os.path.isdir(args.local) else os.path.dirname(path))
        # Keep the folder structure of a tree, one level of subfolders at a time.
        target = parent
        for part in os.path.dirname(rel).split(os.sep):
            if part and part != ".":
                target = _folder(s, part, target)
        info = _upload(s, target, path)
        size = os.path.getsize(path)
        print(f"uploaded: {rel} ({size} bytes) id={info['id']}")
        if args.verify:
            with open(path, "rb") as f:
                want = hashlib.sha256(f.read()).hexdigest()
            got = hashlib.sha256(_read_back(s, info["id"])).hexdigest()
            if want != got:
                print(f"verify FAILED: {rel} (local {want[:12]} drive {got[:12]})")
                failures += 1
            else:
                print(f"verified: {rel} sha256 {want[:12]}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
