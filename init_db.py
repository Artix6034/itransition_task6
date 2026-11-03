import csv
from pathlib import Path

from db import connect

root = Path(__file__).parent
with connect() as conn:
    conn.execute((root / 'sql' / 'schema.sql').read_text(encoding='utf-8'))
    with conn.cursor() as cur:
        for filename, table, columns in [
            ('words.csv', 'words', 'locale,kind,ordinal,value'),
            ('places.csv', 'places', 'locale,ordinal,city,postal_code'),
        ]:
            cur.execute(f'TRUNCATE fake.{table}')
            with cur.copy(f'COPY fake.{table} ({columns}) FROM STDIN') as copy:
                with (root / 'data' / filename).open(encoding='utf-8', newline='') as source:
                    reader = csv.reader(source)
                    next(reader)
                    for row in reader:
                        copy.write_row(row)
    counts = conn.execute('SELECT locale,kind,count(*) AS entries FROM fake.words GROUP BY locale,kind ORDER BY locale,kind').fetchall()
    for row in counts:
        print(row)
