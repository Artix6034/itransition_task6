import math

import pytest

from app import app
from db import connect, generate


def test_repeatability_paging_locale_and_seed():
    first=generate('en_US','42',0)
    generate('de_DE','other request',100)
    assert generate('en_US','42',0)==first
    whole=generate('en_US','42',0,20)
    assert whole[:10]==first
    assert whole[10:]==generate('en_US','42',10)
    assert generate('en_US','43',0)!=first
    assert generate('de_DE','42',0)!=first


def test_dictionary_sizes_and_population_distributions():
    with connect() as conn:
        for row in conn.execute('SELECT locale,kind,count(*) AS n FROM fake.words GROUP BY locale,kind'):
            assert row['n']>=100
    rows=generate('en_US','distribution-check',0,30000)
    z=[math.sin(math.radians(r['latitude'])) for r in rows]
    assert abs(sum(z)/len(z))<.02
    assert abs(sum(v*v for v in z)/len(z)-1/3)<.015
    counts=[0]*10
    for row in rows:
        counts[min(9,int((row['longitude']+180)/36))]+=1
    assert max(abs(n-3000) for n in counts)<250
    assert len({r['email'] for r in rows})==len(rows)
    heights=[r['height_cm'] for r in rows]
    weights=[r['weight_kg'] for r in rows]
    assert abs(sum(heights)/len(rows)-171.5)<.4
    assert abs(sum(weights)/len(rows)-72.5)<.5
    assert abs(sum((x-171.5)**2 for x in heights)/len(rows)-(49+6.5**2))<4


def test_sql_primitives_have_known_results():
    with connect() as conn:
        result=conn.execute('CALL fake.coordinates(%s,%s,%s,%s)',(.5,.5,None,None)).fetchone()
        assert result=={'latitude':0.,'longitude':0.}
        result=conn.execute('CALL fake.normal_value(%s,%s,%s,%s,%s)',(.5,.25,100.,5.,None)).fetchone()
        assert abs(result['result']-100)<1e-12


def test_web_and_input_validation():
    client=app.test_client()
    first=client.get('/api/users?locale=de_DE&seed=42&offset=10').json
    assert len(first)==10 and first[0]['position']==10
    assert first==client.get('/api/users?locale=de_DE&seed=42&offset=10').json
    assert client.get('/?locale=de_DE&seed=42&batch=1').status_code==200
    assert client.get('/?batch=-1').status_code==400
    assert client.get('/api/users?count=1001').status_code==400
    assert client.get('/api/users?locale=unknown').status_code==400
    assert client.get('/docs').status_code==200
