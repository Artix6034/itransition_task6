import os

import psycopg
from psycopg.rows import dict_row


def connect():
    return psycopg.connect(os.environ['DATABASE_URL'], connect_timeout=10, row_factory=dict_row)


def generate(locale, seed, offset, count=10):
    with connect() as conn, conn.cursor() as cursor:
        cursor.execute('CALL fake.generate_users(%s,%s,%s,%s,%s)',
                       (locale, seed, offset, count, 'fake_users'))
        cursor.execute('FETCH ALL FROM fake_users')
        return cursor.fetchall()


def locales():
    with connect() as conn:
        return conn.execute('SELECT code,label FROM fake.locales ORDER BY code').fetchall()
