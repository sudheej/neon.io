import http.client
import io
import json
import threading
import unittest

import app


class RequestValidationTests(unittest.TestCase):
    def setUp(self):
        app.MATCH_TOKEN_SECRET = "test-secret-with-sufficient-entropy"
        with app.LOCK:
            app.SESSIONS.clear()
            for state in app.QUEUES.values():
                state.waiting.clear()
                state.active_matches.clear()
                state.pending_assignments.clear()
                state.last_join_ms.clear()

    def test_rejects_invalid_content_length(self):
        handler = type("Handler", (), {"headers": {"Content-Length": "invalid"}, "rfile": io.BytesIO()})()
        payload, error = app._read_json(handler)
        self.assertIsNone(payload)
        self.assertEqual(error, "invalid_content_length")

    def test_rejects_non_object_json(self):
        body = b"[]"
        handler = type("Handler", (), {"headers": {"Content-Length": str(len(body))}, "rfile": io.BytesIO(body)})()
        payload, error = app._read_json(handler)
        self.assertIsNone(payload)
        self.assertEqual(error, "json_object_required")

    def test_new_players_fill_existing_match_with_unique_credentials(self):
        state = app.QUEUES["mixed"]
        with app.LOCK:
            state.waiting.clear()
            state.active_matches.clear()
            state.pending_assignments.clear()
            state.waiting.append("session-1")
            first = app._allocate_match("mixed")
            first_token = state.pending_assignments["session-1"].match_token
            state.waiting.append("session-2")
            second = app._allocate_match("mixed")
            second_token = state.pending_assignments["session-2"].match_token
        self.assertEqual(first["match_id"], second["match_id"])
        self.assertNotEqual(first_token, second_token)
        self.assertGreaterEqual(len(first_token), 32)

    def test_full_match_keeps_overflow_queued(self):
        original_cap = app.ACTIVE_MATCH_CAP
        original_max = app.MAX_ACTIVE_MATCHES
        app.ACTIVE_MATCH_CAP = 2
        app.MAX_ACTIVE_MATCHES = 1
        state = app.QueueState(
            waiting=app.deque(["overflow"]),
            active_matches={"mixed_existing": ["one", "two"]},
        )
        original_state = app.QUEUES["mixed"]
        app.QUEUES["mixed"] = state
        try:
            self.assertIsNone(app._allocate_match("mixed"))
            self.assertEqual(list(state.waiting), ["overflow"])
        finally:
            app.QUEUES["mixed"] = original_state
            app.ACTIVE_MATCH_CAP = original_cap
            app.MAX_ACTIVE_MATCHES = original_max

    def test_expired_assignment_does_not_create_ghost_queue_entry(self):
        state = app.QueueState(active_matches={"m": ["gone"]})
        state.pending_assignments["gone"] = app.PendingAssignment(
            "gone", "mixed", "m", "127.0.0.1:7000", "token", "actor", 0, 0, 0
        )
        original_state = app.QUEUES["mixed"]
        app.QUEUES["mixed"] = state
        try:
            app._expire_assignments("mixed")
            self.assertEqual(list(state.waiting), [])
            self.assertEqual(state.active_matches, {})
        finally:
            app.QUEUES["mixed"] = original_state

    def test_accepted_assignment_uses_token_expiry(self):
        future = app._timestamp_ms() + 60000
        state = app.QueueState(active_matches={"m": ["active"]})
        state.pending_assignments["active"] = app.PendingAssignment(
            "active", "mixed", "m", "127.0.0.1:7000", "token", "actor", 0, 0, future, True
        )
        original_state = app.QUEUES["mixed"]
        app.QUEUES["mixed"] = state
        try:
            app._expire_assignments("mixed")
            self.assertIn("active", state.pending_assignments)
        finally:
            app.QUEUES["mixed"] = original_state

    def test_match_token_contains_signed_identity_claims(self):
        token = app._issue_match_token("s1", "p1", "m1", "a1", app._timestamp_ms() + 10000)
        encoded, signature = token.split(".")
        expected = app._b64url(app.hmac.new(app.MATCH_TOKEN_SECRET.encode(), encoded.encode(), app.hashlib.sha256).digest())
        self.assertTrue(app.hmac.compare_digest(signature, expected))
        claims = json.loads(app.base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
        self.assertEqual(claims["actor_id"], "a1")

    def test_removing_last_player_releases_match(self):
        state = app.QueueState(active_matches={"match-1": ["session-1"]})
        app._remove_player_from_match(state, "match-1", "session-1")
        self.assertNotIn("match-1", state.active_matches)


class LobbyApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.server = app.ThreadingHTTPServer(("127.0.0.1", 0), app.LobbyHandler)
        except PermissionError as exc:
            raise unittest.SkipTest("local sandbox does not permit loopback sockets") from exc
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def setUp(self):
        app.MATCH_TOKEN_SECRET = "test-secret-with-sufficient-entropy"
        with app.LOCK:
            app.SESSIONS.clear()
            app.RATE_LIMIT_STATE.clear()
            for state in app.QUEUES.values():
                state.waiting.clear()
                state.active_matches.clear()
                state.pending_assignments.clear()
                state.last_join_ms.clear()

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2)
        encoded = json.dumps(body).encode() if body is not None else None
        request_headers = {"Content-Type": "application/json"}
        request_headers.update(headers or {})
        conn.request(method, path, encoded, request_headers)
        response = conn.getresponse()
        payload = json.loads(response.read())
        conn.close()
        return response.status, response.headers, payload

    def auth(self, session="session-1"):
        status, _, _ = self.request("POST", "/v1/auth", {"session_id": session, "player_id": "player-1"})
        self.assertEqual(status, 200)

    def test_queue_requires_authenticated_session(self):
        status, _, payload = self.request("POST", "/v1/queue/join", {"session_id": "unknown", "mode": "mixed"})
        self.assertEqual(status, 401)
        self.assertEqual(payload["error"], "unknown_session")

    def test_auth_join_and_status(self):
        self.auth()
        status, headers, joined = self.request("POST", "/v1/queue/join", {"session_id": "session-1", "mode": "mixed"})
        self.assertEqual(status, 200)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(joined["msg_type"], "match_assigned")
        self.assertGreaterEqual(len(joined["match_token"]), 32)
        status, _, current = self.request("GET", "/v1/queue/status?session_id=session-1&mode=mixed")
        self.assertEqual(status, 200)
        self.assertEqual(current["match_id"], joined["match_id"])
        status, _, accepted = self.request("POST", "/v1/match/accept", {
            "session_id": "session-1",
            "mode": "mixed",
            "match_id": joined["match_id"],
            "match_token": joined["match_token"],
        })
        self.assertEqual(status, 200)
        self.assertTrue(accepted["ok"])
        self.assertTrue(app.QUEUES["mixed"].pending_assignments["session-1"].accepted)

    def test_rejects_invalid_json_shape(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2)
        conn.request("POST", "/v1/auth", b"[]", {"Content-Type": "application/json"})
        response = conn.getresponse()
        self.assertEqual(response.status, 400)
        self.assertEqual(json.loads(response.read())["error"], "json_object_required")
        conn.close()

    def test_rejects_oversized_body_without_reading_it(self):
        status, _, payload = self.request(
            "POST", "/v1/auth", None, {"Content-Length": str(app.MAX_REQUEST_BODY_BYTES + 1)}
        )
        self.assertEqual(status, 413)
        self.assertEqual(payload["error"], "request_body_too_large")


if __name__ == "__main__":
    unittest.main()
