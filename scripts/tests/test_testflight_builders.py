import datetime
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import defer_to_github  # noqa: E402
import prepare_testflight  # noqa: E402

UTC = datetime.timezone.utc


class BuildNumberTests(unittest.TestCase):
    def test_rises_every_minute_and_starts_above_the_old_scheme(self):
        first = prepare_testflight.build_number(datetime.datetime(2026, 11, 17, 20, 0, tzinfo=UTC))
        later = prepare_testflight.build_number(datetime.datetime(2026, 11, 17, 20, 1, tzinfo=UTC))
        self.assertGreater(first, 10901)
        self.assertEqual(later, first + 1)

    def test_stays_a_small_whole_number_for_decades(self):
        far = prepare_testflight.build_number(datetime.datetime(2060, 1, 1, tzinfo=UTC))
        self.assertLess(far, 2**31)


class DeferToGitHubTests(unittest.TestCase):
    queued = {'status': 'queued', 'html_url': 'u'}

    def test_github_has_it_once_a_runner_picks_it_up(self):
        self.assertEqual(defer_to_github.decide(self.queued, [{'runner_name': 'GitHub Actions 1'}], 30), 'github')

    def test_keeps_waiting_while_queued(self):
        self.assertEqual(defer_to_github.decide(self.queued, [{'status': 'queued'}], 60), 'wait')

    def test_builds_here_when_no_runner_comes(self):
        self.assertEqual(defer_to_github.decide(self.queued, [{}], defer_to_github.WAIT_SECONDS), 'here')

    def test_builds_here_when_github_cancelled_it_unstarted(self):
        cancelled = {'status': 'completed', 'conclusion': 'cancelled'}
        self.assertEqual(defer_to_github.decide(cancelled, [{'status': 'completed'}], 0), 'here')

    def test_a_github_run_that_ran_and_failed_is_still_githubs(self):
        failed = {'status': 'completed', 'conclusion': 'failure'}
        self.assertEqual(defer_to_github.decide(failed, [{'runner_name': 'r', 'steps': [{}]}], 0), 'github')

    def test_waits_briefly_for_github_to_create_the_run(self):
        self.assertEqual(defer_to_github.decide(None, [], 20), 'wait')
        self.assertEqual(defer_to_github.decide(None, [], defer_to_github.NO_RUN_SECONDS), 'here')


if __name__ == '__main__':
    unittest.main()


KEY_BODY = 'MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg' + 'A' * 100
KEY_PEM = ('-----BEGIN PRIVATE KEY-----\n' + '\n'.join(KEY_BODY[i:i + 64] for i in range(0, len(KEY_BODY), 64))
           + '\n-----END PRIVATE KEY-----\n')


class PrivateKeyTests(unittest.TestCase):
    PEM = KEY_PEM

    def test_accepts_the_file_as_is(self):
        self.assertEqual(prepare_testflight.private_key_pem(self.PEM), self.PEM)

    def test_accepts_base64_of_the_file(self):
        import base64
        encoded = base64.b64encode(self.PEM.encode()).decode()
        self.assertEqual(prepare_testflight.private_key_pem(encoded + '\n'), self.PEM)

    def test_accepts_lost_line_breaks(self):
        self.assertEqual(prepare_testflight.private_key_pem(self.PEM.replace('\n', ' ')), self.PEM)
        self.assertEqual(prepare_testflight.private_key_pem(self.PEM.replace('\n', '\\n')), self.PEM)

    def test_rejects_anything_else_without_echoing_it(self):
        with self.assertRaises(ValueError) as caught:
            prepare_testflight.private_key_pem('not a key at all')
        self.assertNotIn('not a key', str(caught.exception))
