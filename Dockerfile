FROM mdillon/postgis:9.4

ENV POSTGRES_DB gis

RUN apt-get update && apt-get install python3 python3-pip libpq-dev -y && pip3 install bottle && pip3 install psycopg2

COPY data/ /tmp/data/
COPY app/ /tmp/app/

COPY init.sql /docker-entrypoint-initdb.d/
COPY start_server.sh /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/start_server.sh

EXPOSE 8080
