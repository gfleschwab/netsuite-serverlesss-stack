# tests/test_fcm311_07_customer_extract.py
# Run: python -m unittest discover -s tests
import csv
import importlib.util
import io
import pathlib
import unittest
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "glue-scripts" / "fcm311-07-netsuite-customer-extract.py"
spec = importlib.util.spec_from_file_location("customer_extract", SCRIPT)
job = importlib.util.module_from_spec(spec)
spec.loader.exec_module(job)

LA = ZoneInfo("America/Los_Angeles")


class FakeClient:
    def __init__(self, pages):
        self.pages = pages
        self.queries = []

    def query(self, q, limit):
        self.queries.append(q)
        return self.pages[len(self.queries) - 1]


class QueryTests(unittest.TestCase):
    def test_columns_match_boomi_statement_and_include_toplevelparent(self):
        self.assertEqual(len(job.CUSTOMER_COLUMNS), len(set(job.CUSTOMER_COLUMNS)))
        self.assertIn("toplevelparent", job.CUSTOMER_COLUMNS)
        i = job.CUSTOMER_COLUMNS.index("toplevelparent")
        self.assertEqual(job.CUSTOMER_COLUMNS[i - 1:i + 2], ["title", "toplevelparent", "unbilledorderssearch"])
        self.assertTrue((job.DATETIME_COLUMNS | job.DATE_COLUMNS) <= set(job.CUSTOMER_COLUMNS))

    def test_build_query_filters_and_keyset_paginates(self):
        q = job.build_query("2026-10-23 04:30:00", 42)
        self.assertIn("FROM Customer WHERE lastmodifieddate >= TO_DATE('2026-10-23 04:30:00', 'YYYY-MM-DD HH24:MI:SS')", q)
        self.assertTrue(q.endswith("AND id > 42 ORDER BY id"))
        self.assertIn("TO_CHAR(lastmodifieddate, 'YYYY-MM-DD HH24:MI:SS') AS lastmodifieddate", q)
        self.assertIn(", toplevelparent,", q)


class WatermarkTests(unittest.TestCase):
    def test_parse_utc_formats(self):
        expected = datetime(2026, 10, 23, 11, 30, tzinfo=timezone.utc)
        self.assertEqual(job.parse_utc("2026-10-23T11:30:00Z"), expected)
        self.assertEqual(job.parse_utc("20261023 113000"), expected)
        self.assertEqual(job.parse_utc("2026-10-23T04:30:00-07:00"), expected)

    def test_override_wins_and_overlap_is_applied(self):
        got = job.resolve_from_date("20261020 000000", "2026-10-23T11:30:00Z", 10)
        self.assertEqual(got, datetime(2026, 10, 19, 23, 50, tzinfo=timezone.utc))
        got = job.resolve_from_date("auto", "2026-10-23T11:30:00Z", 0)
        self.assertEqual(got, datetime(2026, 10, 23, 11, 30, tzinfo=timezone.utc))

    def test_missing_watermark_fails(self):
        with self.assertRaises(ValueError):
            job.resolve_from_date("auto", None, 0)


class FormatTests(unittest.TestCase):
    def test_datetime_converted_to_utc_and_date_kept(self):
        self.assertEqual(job.format_value("lastmodifieddate", "2018-09-11 18:17:41", LA), "20180912 011741.000")
        self.assertEqual(job.format_value("startdate", "2018-06-23 00:00:00", LA), "20180623 000000.000")
        self.assertEqual(job.format_value("isinactive", "F", LA), "F")
        self.assertEqual(job.format_value("isperson", True, LA), "T")
        self.assertEqual(job.format_value("creditlimit", 0.0, LA), "0.0")
        self.assertEqual(job.format_value("email", None, LA), "")

    def test_row_follows_column_order_and_ignores_links(self):
        row = job.to_row({"id": "7", "links": [], "toplevelparent": "5"}, LA)
        self.assertEqual(len(row), len(job.CUSTOMER_COLUMNS))
        self.assertEqual(row[job.CUSTOMER_COLUMNS.index("id")], "7")
        self.assertEqual(row[job.CUSTOMER_COLUMNS.index("toplevelparent")], "5")

    def test_writer_matches_boomi_flat_file(self):
        buf = io.StringIO()
        job.new_writer(buf).writerow(["", 'say "hi"', "a|b"])
        self.assertEqual(buf.getvalue(), '""|"say ""hi"""|"a|b"\n')
        self.assertEqual(next(csv.reader(io.StringIO(buf.getvalue()), delimiter="|")), ["", 'say "hi"', "a|b"])


class ExtractTests(unittest.TestCase):
    def test_paginates_by_last_id_until_no_more(self):
        client = FakeClient([
            {"items": [{"id": "1"}, {"id": "5"}], "hasMore": True},
            {"items": [{"id": "9"}], "hasMore": False},
        ])
        buf = io.StringIO()
        total = job.extract(client, "2026-10-23 04:30:00", LA, job.new_writer(buf))
        self.assertEqual(total, 3)
        self.assertTrue(client.queries[0].endswith("id > 0 ORDER BY id"))
        self.assertTrue(client.queries[1].endswith("id > 5 ORDER BY id"))
        self.assertEqual(len(buf.getvalue().splitlines()), 3)

    def test_empty_result(self):
        client = FakeClient([{"items": [], "hasMore": False}])
        self.assertEqual(job.extract(client, "2026-10-23 04:30:00", LA, job.new_writer(io.StringIO())), 0)


if __name__ == "__main__":
    unittest.main()
