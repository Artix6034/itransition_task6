import argparse
import json
import platform
import statistics
import time

from db import connect

parser = argparse.ArgumentParser()
parser.add_argument('--count', type=int, default=100000)
parser.add_argument('--repeats', type=int, default=3)
args = parser.parse_args()
timings = []
with connect() as conn, conn.cursor() as cur:
    version = conn.execute('SHOW server_version').fetchone()['server_version']
    cur.execute('CALL fake.generate_users(%s,%s,%s,%s,%s)', ('en_US','warmup',0,1000,'warmup'))
    cur.execute('CLOSE warmup')
    for _ in range(args.repeats):
        start = time.perf_counter()
        cur.execute('CALL fake.generate_users(%s,%s,%s,%s,%s)', ('en_US','benchmark',0,args.count,'bench'))
        cur.execute('CLOSE bench')
        timings.append(time.perf_counter()-start)
result = {'users':args.count,'repeats':args.repeats,'seconds':timings,
          'median_users_per_second':round(args.count/statistics.median(timings),1),
          'postgresql':version,'platform':platform.platform(),
          'warmup_users':1000,
          'measurement':'SQL generation and temp table materialization; excludes transfer and HTML rendering'}
print(json.dumps(result,indent=2))
