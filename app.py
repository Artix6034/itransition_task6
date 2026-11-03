import os
from pathlib import Path

import psycopg
from flask import Flask, jsonify, render_template, request, send_file

import db

app = Flask(__name__)


@app.get('/')
def index():
    locale = request.args.get('locale', 'en_US')
    seed = request.args.get('seed', '42')
    try:
        batch = int(request.args.get('batch', '0'))
        if batch < 0 or batch > 100000000 or len(seed) > 128:
            raise ValueError
    except ValueError:
        return 'Invalid batch or seed.', 400
    try:
        choices = db.locales()
        if locale not in {item['code'] for item in choices}:
            return 'Unknown locale.', 400
        rows = db.generate(locale, seed, batch * 10)
    except (psycopg.Error, KeyError):
        app.logger.exception('Database request failed')
        return render_template('index.html', error='Database unavailable. Check DATABASE_URL and run init_db.py.',
                               rows=[], choices=[], locale=locale, seed=seed, batch=batch), 503
    return render_template('index.html', rows=rows, choices=choices, locale=locale, seed=seed, batch=batch)


@app.get('/api/users')
def users():
    try:
        offset = int(request.args.get('offset', '0'))
        count = int(request.args.get('count', '10'))
        seed = request.args.get('seed', '42')
        if not 0 <= offset <= 10**12 or not 1 <= count <= 1000 or len(seed) > 128:
            raise ValueError
        locale = request.args.get('locale', 'en_US')
        if locale not in {item['code'] for item in db.locales()}:
            raise ValueError
        return jsonify(db.generate(locale, seed, offset, count))
    except ValueError:
        return jsonify(error='Invalid locale, seed, offset or count (1..1000).'), 400
    except (psycopg.Error, KeyError):
        app.logger.exception('API database request failed')
        return jsonify(error='Database unavailable.'), 503


@app.get('/docs')
def docs():
    return send_file(Path(__file__).parent / 'docs' / 'procedures.html')


@app.get('/health')
def health():
    try:
        db.locales()
        return jsonify(status='ok')
    except (psycopg.Error, KeyError):
        return jsonify(status='database unavailable'), 503


if __name__ == '__main__':
    from waitress import serve
    serve(app, host=os.getenv('HOST', '127.0.0.1'), port=int(os.getenv('PORT', '5066')))
