import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("processing", Path(__file__).resolve().parents[1] / "wait_for_testflight.py")
processing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(processing)


class TestProcessing(unittest.TestCase):
    def run_states(self, states):
        elapsed = [0]
        responses = iter(states)
        def request(path, params):
            state = next(responses)
            if state is None:
                return {"data": []}
            return {"data": [{"id": "build-id", "attributes": {"version": "3201", "processingState": state}}]}
        return processing.await_build("app", "3201", timeout=120, request=request,
                                      sleep=lambda seconds: elapsed.__setitem__(0, elapsed[0] + seconds), clock=lambda: elapsed[0])

    def test_waits_for_exact_build_after_upload_and_processing(self):
        self.assertEqual(self.run_states([None, "PROCESSING", "VALID"])["id"], "build-id")

    def test_rejected_build_is_not_reported_as_ready(self):
        for state in ["FAILED", "INVALID"]:
            with self.subTest(state=state), self.assertRaises(RuntimeError):
                self.run_states([state])

    def test_processing_never_finishes_instead_of_claiming_success(self):
        with self.assertRaises(TimeoutError):
            self.run_states(["PROCESSING"] * 4)

    def test_jwt_signature_keeps_sign_padding_and_fixed_width(self):
        first = b"\x00\x80" + b"\x01" * 31
        second = b"\x01"
        body = b"\x02" + bytes([len(first)]) + first + b"\x02\x01" + second
        self.assertEqual(processing.raw_signature(b"\x30" + bytes([len(body)]) + body), first[1:] + b"\0" * 31 + second)


if __name__ == "__main__":
    unittest.main()
