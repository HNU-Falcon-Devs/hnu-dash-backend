"""Synthetic tests for the CSV -> authorized RPC payload boundary."""
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from csv_to_import_json import convert

HEADER = "student_id,full_name,program_code,year_level\n"


class RosterCsvTests(unittest.TestCase):
    def convert_text(self, body):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.csv"
            path.write_text(body, encoding="utf-8")
            return convert(path)

    def test_quoted_name_and_leading_zero_identifier(self):
        payload = self.convert_text(HEADER + '00001234,"Demo, Student",BSIT,2\n')
        self.assertEqual(payload, {"rows": [{
            "student_id": "00001234", "full_name": "Demo, Student",
            "program_code": "BSIT", "year_level": 2
        }]})

    def test_duplicate_identifiers_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate student ID"):
            self.convert_text(HEADER +
                "00001234,First Demo,BSIT,1\n00001234,Second Demo,BSIT,2\n")

    def test_bad_year_level_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid program or year level"):
            self.convert_text(HEADER + "00001234,Demo,BSIT,9\n")

    def test_malformed_csv_row_rejected(self):
        with self.assertRaisesRegex(ValueError, "wrong number of columns"):
            self.convert_text(HEADER + "00001234,Demo,BSIT,1,unexpected\n")

    def test_wrong_header_rejected(self):
        with self.assertRaisesRegex(ValueError, "Expected CSV headers"):
            self.convert_text("name,student_id\nDemo,00001234\n")

    def test_empty_roster_rejected(self):
        with self.assertRaisesRegex(ValueError, "cannot be empty"):
            self.convert_text(HEADER)


if __name__ == "__main__":
    unittest.main()
