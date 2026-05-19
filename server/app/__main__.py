"""Entrypoint: `python -m app`."""
from __future__ import annotations

import os

from .server import create_app, socketio


def main() -> None:
    app = create_app()
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "5000"))
    socketio.run(app, host=host, port=port, allow_unsafe_werkzeug=False)


if __name__ == "__main__":
    main()
