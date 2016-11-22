--postgis settings taken from example
--
SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

CREATE SCHEMA tiger;
ALTER SCHEMA tiger OWNER TO postgres;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;
CREATE SCHEMA topology;
ALTER SCHEMA topology OWNER TO postgres;
CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;
SET search_path = public, pg_catalog;
--

--create airbnb table and import data
CREATE TABLE airbnb_listing(
	id serial primary key,
	room_id integer,
	host_id integer,
	room_type text,
	borough text,
	neighborhood text,
	reviews integer,
	overall_satisfaction real,
	accommodates integer,
	bedrooms integer,
	bathrooms integer,
	price integer,
	minstay integer,
	latitude double precision,
	longitude double precision,
	coordinate geometry(Point,4326),
	park_name text,
	park_distance integer,
	noise_level integer,
	polution_level integer
);

COPY airbnb_listing(room_id, host_id, room_type, borough, neighborhood, reviews, overall_satisfaction, accommodates, bedrooms, bathrooms, price, minstay, latitude, longitude) FROM '/tmp/data/airbnb_listing.csv' DELIMITER ',' CSV HEADER;
UPDATE airbnb_listing SET coordinate = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);

CREATE INDEX airbnb_listing_index ON airbnb_listing USING gist (coordinate) WITH (fillfactor=100);--fillfactor 100 good for static data

--create nature park table and import data
CREATE TABLE nature_park(
	id serial primary key,
	name text,
	geojson_str text,
	shape geometry(Geometry,4326)
);

COPY nature_park(name, geojson_str) FROM '/tmp/data/parks.csv' DELIMITER ';' QUOTE '''' CSV;
UPDATE nature_park SET shape = ST_SetSRID(ST_GeomFromGeoJSON(geojson_str), 4326);

CREATE INDEX nature_park_index ON nature_park USING gist (shape) WITH (fillfactor=100);

--create air polution table and import data

CREATE TABLE air_polution(
	id serial primary key,
	level integer,
	geojson_str text,
	shape geometry(Geometry,4326)
);

COPY air_polution(level, geojson_str) FROM '/tmp/data/polution.csv' DELIMITER ';' QUOTE '''' CSV;
UPDATE air_polution SET shape = ST_SetSRID(ST_GeomFromGeoJSON(geojson_str), 4326);

CREATE INDEX air_polution_index ON air_polution USING gist (shape) WITH (fillfactor=100);

--create noise table and import data
CREATE TABLE noise_level(
	id serial primary key,
	level integer,
	geojson_str text,
	shape geometry(Geometry,4326)
);

COPY noise_level(level, geojson_str) FROM '/tmp/data/noise.csv' DELIMITER ';' QUOTE '''' CSV;
UPDATE noise_level SET shape = ST_SetSRID(ST_GeomFromGeoJSON(geojson_str), 4326);

CREATE INDEX noise_level_index ON noise_level USING gist (shape) WITH (fillfactor=100);

--precompute geodata for listings--

--update listing with park info, the subquery finds nearest nature park for each listing 
--ST_DISTANCE with geometry (fast, returns degrees) is used first to find the closest park, then the ST_DISTANCE on geography (slow, returns meters) runs only on final data
--this brings significant speedup (72s vs 6s) 
UPDATE airbnb_listing
SET park_name=subquery.park_name,
    park_distance=subquery.park_distance
FROM (SELECT listing_id,park_name,ST_DISTANCE(coordinate::geography,shape::geography)::int as park_distance FROM (
SELECT DISTINCT ON (l.id) l.id as listing_id,l.coordinate,n.name as park_name,n.shape FROM airbnb_listing l,  nature_park n ORDER BY l.id,ST_DISTANCE(l.coordinate,n.shape) asc
) z) AS subquery
WHERE airbnb_listing.id=subquery.listing_id;


--update listing with noise info, the subquery finds noise level for each listing, overlap in polygons exist => selects higher noise with order+distinct
UPDATE airbnb_listing
SET noise_level=subquery.noise_level
FROM (SELECT DISTINCT ON(l.id) l.id as listing_id,n.level as noise_level FROM airbnb_listing l, noise_level n WHERE ST_CONTAINS(n.shape, l.coordinate) ORDER BY l.id asc, n.level desc) AS subquery
WHERE airbnb_listing.id=subquery.listing_id;


--update listing with air polution info, the subquery finds polution level for each listing, no overlap in polution polygons => distinct not needed
UPDATE airbnb_listing
SET polution_level=subquery.polution_level
FROM (SELECT l.id as listing_id,p.level as polution_level FROM airbnb_listing l, air_polution p WHERE ST_CONTAINS(p.shape, l.coordinate)) AS subquery
WHERE airbnb_listing.id=subquery.listing_id;


CREATE INDEX airbnb_listing_noise_level_index ON airbnb_listing(noise_level);
CREATE INDEX airbnb_listing_park_distance_index ON airbnb_listing(park_distance);
CREATE INDEX airbnb_listing_polution_level_index ON airbnb_listing(polution_level);
