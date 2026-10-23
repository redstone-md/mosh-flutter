import json
import unittest

from cpu_profile import error_summary


class ExportErrorPrivacyTest(unittest.TestCase):
    def test_exports_only_error_identifiers_without_arguments_paths_or_messages(self):
        text = r'''System.NullReferenceException: private-message secret=private-secret
Could not find C:\Users\private-user\private-module.dll Args: private-argument
   at PerfViewExtensibility.Extensions.ExecuteUserCommand(String private-parameter)
file.cs(10,3): error CS0012: private-message
https://private-host/path?token=private-token&access_token=private-access
'''
        result = error_summary(text)
        self.assertEqual(result, {
            'exception_types': ['NullReferenceException'],
            'compiler_codes': ['CS0012'],
            'methods': ['PerfViewExtensibility.Extensions.ExecuteUserCommand'],
        })
        self.assertNotIn('private-', json.dumps(result))

    def test_unknown_messages_do_not_escape(self):
        self.assertEqual(error_summary('Unhandled private-secret'), {
            'exception_types': [], 'compiler_codes': [], 'methods': [],
        })


if __name__ == '__main__':
    unittest.main()
