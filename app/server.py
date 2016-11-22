from bottle import route, run, template, static_file, request
import json
import psycopg2
import sys
import time

connected = False
retry = 30
while not connected and (retry > 0):
	try:
		conn = psycopg2.connect("dbname='gis' user='postgres' host='localhost' port='5432' password=''")
		connected = True
	except:
		print("Unable to connect to the database, retrying..")
		retry -= 1
		time.sleep(5)

if not connected:
	print("Unable to connect to the database, exiting..")
	sys.exit(-1);
print("Connected to the database!")

cur=conn.cursor()
cur.execute("SELECT ST_AsGeoJSON(coordinate) as res FROM airbnb_listing")
rows = cur.fetchone()

@route('/dependencies/<filename>')
def dependencies_static(filename):
	return static_file(filename, root='./dependencies/')

@route('/')
def index_static():
	return static_file('index.html', root='.')


@route('/parks')
def parks():
	cur.execute("SELECT row_to_json(fc)  FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type , ST_AsGeoJSON(shape)::json As geometry, row_to_json((SELECT l FROM (SELECT name) as l )) As properties FROM nature_park As a_l   ) As f )  As fc;")
	rows = cur.fetchone()
	return rows[0]

@route('/polution')
def polution():
	cur.execute("SELECT row_to_json(fc) FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON(shape)::json As geometry, row_to_json((SELECT l FROM (SELECT level) as l )) As properties FROM air_polution As a_l   ) As f )  As fc;")
	rows = cur.fetchone()
	return rows[0]


@route('/noise')
def noise():
	cur.execute("SELECT row_to_json(fc) FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON(shape)::json As geometry, row_to_json((SELECT l FROM (SELECT level) as l )) As properties FROM noise_level As a_l   ) As f )  As fc;")
	rows = cur.fetchone()
	return rows[0]
	
#default call which returns everything from airbnb_listing
@route('/default')
def default():
	cur.execute("SELECT row_to_json(fc) FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON(coordinate)::json As geometry, row_to_json((SELECT l FROM (SELECT room_id, room_type , overall_satisfaction, accommodates, price, minstay, park_name, park_distance, noise_level,polution_level) as l )) As properties FROM airbnb_listing As a_l   ) As f )  As fc;")
	rows = cur.fetchone()
	return rows[0]
	
#using prepared statement to avoid sql injection
@route('/search')
def search():
	#parameters -> max_park_distance, noise_min, noise_max, polution_min, polution_max
	max_park_distance = -1
	if 'max_park_distance' in request.query and request.query['max_park_distance'] != '':
		max_park_distance = int(request.query['max_park_distance'])
	
	noise_min = int(request.query['noise_min']) or 0
	noise_max = int(request.query['noise_max']) or 100
	
	polution_min = int(request.query['polution_min']) or 0
	polution_max =  int(request.query['polution_max']) or 5
	
	if max_park_distance >= 0:
		cur.execute("SELECT row_to_json(fc) FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON(coordinate)::json As geometry, row_to_json((SELECT l FROM (SELECT room_id, room_type , overall_satisfaction, accommodates, price, minstay, park_name, park_distance, noise_level,polution_level) as l )) As properties FROM airbnb_listing As a_l WHERE (noise_level >= %s AND noise_level <= %s) AND (polution_level >= %s AND polution_level <= %s) AND park_distance <= %s  ) As f )  As fc;", (noise_min,noise_max, polution_min,polution_max, max_park_distance))
	else:
		cur.execute("SELECT row_to_json(fc) FROM ( SELECT 'FeatureCollection' As type, array_to_json(array_agg(f)) As features FROM (SELECT 'Feature' As type, ST_AsGeoJSON(coordinate)::json As geometry, row_to_json((SELECT l FROM (SELECT room_id, room_type , overall_satisfaction, accommodates, price, minstay, park_name, park_distance, noise_level,polution_level) as l )) As properties FROM airbnb_listing As a_l WHERE (noise_level >= %s AND noise_level <= %s) AND (polution_level >= %s AND polution_level <= %s)) As f )  As fc;",(noise_min,noise_max, polution_min,polution_max))
	
	rows = cur.fetchone()
	return rows[0]

run(host='0.0.0.0', port=8080)
