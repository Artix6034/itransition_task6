CREATE SCHEMA IF NOT EXISTS fake;

CREATE TABLE IF NOT EXISTS fake.locales (
    code text PRIMARY KEY,
    label text NOT NULL,
    country text NOT NULL,
    address_templates text[] NOT NULL,
    name_templates text[] NOT NULL,
    phone_templates text[] NOT NULL,
    titles text[] NOT NULL,
    eye_colors text[] NOT NULL
);
CREATE TABLE IF NOT EXISTS fake.words (
    locale text REFERENCES fake.locales(code),
    kind text NOT NULL,
    ordinal integer NOT NULL,
    value text NOT NULL,
    PRIMARY KEY (locale, kind, ordinal)
);
CREATE TABLE IF NOT EXISTS fake.places (
    locale text REFERENCES fake.locales(code),
    ordinal integer NOT NULL,
    city text NOT NULL,
    postal_code text NOT NULL,
    PRIMARY KEY (locale, ordinal)
);

INSERT INTO fake.locales VALUES
('en_US', 'English / USA', 'United States',
 ARRAY['{number} {street}, {city}, {postal}, {country}', '{number} {street}, Apt {unit}, {city}, {postal}, {country}'],
 ARRAY['{first} {last}', '{first} {middle} {last}', '{title} {first} {last}'],
 ARRAY['+1 (202) 555-{digits}', '(202) 555-{digits}', '202-555-{digits}'],
 ARRAY['Mr.', 'Ms.'], ARRAY['brown','blue','green','hazel','gray']),
('de_DE', 'Deutsch / Deutschland', 'Deutschland',
 ARRAY['{street} {number}, {postal} {city}, {country}', '{street} {number}, Wohnung {unit}, {postal} {city}, {country}'],
 ARRAY['{first} {last}', '{first} {middle} {last}', '{title} {first} {last}'],
 ARRAY['+49 30 5550{digits}', '030 / 5550{digits}', '(030) 5550-{digits}'],
 ARRAY['Herr', 'Frau'], ARRAY['braun','blau','grün','haselnussbraun','grau'])
ON CONFLICT (code) DO UPDATE SET label=EXCLUDED.label, country=EXCLUDED.country,
address_templates=EXCLUDED.address_templates, name_templates=EXCLUDED.name_templates,
phone_templates=EXCLUDED.phone_templates, titles=EXCLUDED.titles, eye_colors=EXCLUDED.eye_colors;

-- Open-interval uniforms. Each field has its own stream, independent of request order.
CREATE OR REPLACE PROCEDURE fake.uniforms(
    IN p_locale text, IN p_seed text, IN p_position bigint,
    IN p_count integer, INOUT result double precision[]
) LANGUAGE plpgsql AS $$
BEGIN
    SELECT array_agg((('x' || substr(md5(json_build_array(p_locale,p_seed,p_position,s)::text),1,13))::bit(52)::bigint + 0.5) / 4503599627370496.0 ORDER BY s)
    INTO result FROM generate_series(1,p_count) s;
END $$;

CREATE OR REPLACE PROCEDURE fake.normal_value(
    IN u1 double precision, IN u2 double precision,
    IN mean double precision, IN deviation double precision,
    INOUT result double precision
) LANGUAGE plpgsql AS $$
BEGIN
    IF u1<=0 OR u1>=1 OR u2<=0 OR u2>=1 OR deviation<0 THEN
        RAISE EXCEPTION 'Invalid normal distribution parameters';
    END IF;
    result := mean + deviation * sqrt(-2*ln(u1)) * cos(2*pi()*u2);
END $$;

CREATE OR REPLACE PROCEDURE fake.coordinates(
    IN u1 double precision, IN u2 double precision,
    INOUT latitude double precision, INOUT longitude double precision
) LANGUAGE plpgsql AS $$
BEGIN
    latitude := degrees(asin(2*u1-1));
    longitude := 360*u2-180;
END $$;

CREATE OR REPLACE PROCEDURE fake.format_text(
    IN template text, IN keys text[], IN vals text[], INOUT result text
) LANGUAGE plpgsql AS $$
BEGIN
    result := template;
    FOR i IN 1..cardinality(keys) LOOP
        result := replace(result,'{' || keys[i] || '}',vals[i]);
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE fake.person_name(
    IN u double precision[], IN firsts text[], IN lasts text[],
    IN templates text[], IN title text,
    INOUT first_name text, INOUT last_name text, INOUT full_name text
) LANGUAGE plpgsql AS $$
DECLARE middle_name text;
BEGIN
    first_name := firsts[1+floor(u[2]*cardinality(firsts))::integer];
    last_name := lasts[1+floor(u[3]*cardinality(lasts))::integer];
    middle_name := firsts[1+floor(u[4]*cardinality(firsts))::integer];
    CALL fake.format_text(templates[1+floor(u[5]*cardinality(templates))::integer],
        ARRAY['first','middle','last','title'], ARRAY[first_name,middle_name,last_name,title],full_name);
END $$;

CREATE OR REPLACE PROCEDURE fake.address_text(
    IN u double precision[], IN streets text[], IN cities text[], IN postals text[],
    IN templates text[], IN country text, INOUT result text
) LANGUAGE plpgsql AS $$
DECLARE place_index integer := 1+floor(u[7]*cardinality(cities))::integer;
BEGIN
    CALL fake.format_text(templates[1+floor(u[10]*cardinality(templates))::integer],
        ARRAY['number','street','city','postal','country','unit'],
        ARRAY[(1+floor(u[6]*999))::integer::text,streets[1+floor(u[8]*cardinality(streets))::integer],
              cities[place_index],postals[place_index],country,(1+floor(u[9]*99))::integer::text],result);
END $$;

CREATE OR REPLACE PROCEDURE fake.contact_text(
    IN u double precision[], IN templates text[], IN first_name text,
    IN last_name text, IN p_position bigint,
    INOUT phone text, INOUT email text
) LANGUAGE plpgsql AS $$
DECLARE handle text;
BEGIN
    CALL fake.format_text(templates[1+floor(u[11]*cardinality(templates))::integer],
        ARRAY['digits'],ARRAY['01' || lpad(floor(u[12]*100)::integer::text,2,'0')],phone);
    handle := lower(first_name || '.' || last_name);
    handle := replace(replace(replace(replace(handle,'ä','ae'),'ö','oe'),'ü','ue'),'ß','ss');
    handle := regexp_replace(translate(handle,'áàâéèêíìîóòôúùûñç','aaaeeeiiiooouuunc'),'[^a-z0-9.]','','g');
    email := handle || '.' || p_position::text || '@example.test';
END $$;

CREATE OR REPLACE PROCEDURE fake.generate_users(
    IN p_locale text, IN p_seed text, IN p_offset bigint, IN p_count integer,
    INOUT result refcursor DEFAULT 'fake_users'
) LANGUAGE plpgsql AS $$
DECLARE
    cfg fake.locales%ROWTYPE;
    males text[]; females text[]; lasts text[]; streets text[];
    cities text[]; postals text[]; firsts text[];
    u double precision[]; pos bigint; gender integer;
    first_name text; last_name text; full_name text; address text; phone text; email text;
    latitude double precision; longitude double precision;
    height double precision; weight double precision;
BEGIN
    IF p_offset<0 OR p_offset>1000000000000 OR p_count<1 OR p_count>1000000 OR length(p_seed)>128 THEN
        RAISE EXCEPTION 'offset must be 0..1e12, count 1..1000000, seed at most 128 characters';
    END IF;
    SELECT * INTO cfg FROM fake.locales WHERE code=p_locale;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unsupported locale: %',p_locale; END IF;
    SELECT array_agg(value ORDER BY ordinal) INTO males FROM fake.words WHERE locale=p_locale AND kind='first_male';
    SELECT array_agg(value ORDER BY ordinal) INTO females FROM fake.words WHERE locale=p_locale AND kind='first_female';
    SELECT array_agg(value ORDER BY ordinal) INTO lasts FROM fake.words WHERE locale=p_locale AND kind='surname';
    SELECT array_agg(value ORDER BY ordinal) INTO streets FROM fake.words WHERE locale=p_locale AND kind='street';
    SELECT array_agg(city ORDER BY ordinal),array_agg(postal_code ORDER BY ordinal) INTO cities,postals
        FROM fake.places WHERE locale=p_locale;
    IF males IS NULL OR females IS NULL OR lasts IS NULL OR streets IS NULL OR cities IS NULL THEN
        RAISE EXCEPTION 'Lookup data is missing. Run init_db.py';
    END IF;
    CREATE TEMP TABLE IF NOT EXISTS generated_users (
        position bigint, full_name text, address text, latitude double precision,
        longitude double precision, height_cm double precision, weight_kg double precision,
        eye_color text, phone text, email text
    ) ON COMMIT DROP;
    TRUNCATE pg_temp.generated_users;
    FOR i IN 0..p_count-1 LOOP
        pos := p_offset+i;
        CALL fake.uniforms(p_locale,p_seed,pos,19,u);
        gender := CASE WHEN u[1]<0.5 THEN 1 ELSE 2 END;
        firsts := CASE WHEN gender=1 THEN males ELSE females END;
        CALL fake.person_name(u,firsts,lasts,cfg.name_templates,cfg.titles[gender],first_name,last_name,full_name);
        CALL fake.address_text(u,streets,cities,postals,cfg.address_templates,cfg.country,address);
        CALL fake.coordinates(u[13],u[14],latitude,longitude);
        CALL fake.normal_value(u[15],u[16],CASE WHEN gender=1 THEN 178.0 ELSE 165.0 END,7.0,height);
        CALL fake.normal_value(u[17],u[18],CASE WHEN gender=1 THEN 80.0 ELSE 65.0 END,12.0,weight);
        CALL fake.contact_text(u,cfg.phone_templates,first_name,last_name,pos,phone,email);
        INSERT INTO pg_temp.generated_users VALUES (pos,full_name,address,latitude,longitude,
            height,weight,cfg.eye_colors[1+floor(u[19]*cardinality(cfg.eye_colors))::integer],phone,email);
    END LOOP;
    OPEN result FOR SELECT * FROM pg_temp.generated_users ORDER BY position;
END $$;
