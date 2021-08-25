#!/bin/bash

set -x


export PGDATABASE=${PGDATABASE:-gis}
export PGHOST=${PGHOST:-127.0.0.1}
export PGPORT=${PGPORT:-5432}
export PGUSER=${PGUSER:-renderer}

if [ ! -z "${PGDATABASE}" ] ; then
    sed -i "/dbname/ s/\"dbname\"/\"${PGDATABASE}\"/" /home/renderer/src/openstreetmap-carto/project.mml
fi

if [ ! -z "${PGPORT}" ] ; then
    sed -i "/port/ s/\"port\"/\"${PGPORT}\"/" /home/renderer/src/openstreetmap-carto/project.mml
fi

if [ ! -z "${PGHOST}" ] ; then
    sed -i "/host/ s/\"host\"/\"${PGHOST}\"/" /home/renderer/src/openstreetmap-carto/project.mml
fi

if [ ! -z "${PGPASS}" ] ; then
    sed -i "/password/ s/\"password\"/\"${PGPASS}\"/" /home/renderer/src/openstreetmap-carto/project.mml
fi

if [ ! -z "${PGUSER}" ] ; then
    sed -i "/user/ s/\"user\"/\"${PGUSER}\"/" /home/renderer/src/openstreetmap-carto/project.mml
fi

carto /home/renderer/src/openstreetmap-carto/project.mml > /home/renderer/src/openstreetmap-carto/mapnik.xml

su postgres -c 'echo "${PGHOST}:${PGPORT}:${PGDATABASE}:${PGUSER}:${PGPASS}" >> ~/.pgpass '
su postgres -c 'chmod 0600 ~/.pgpass'

function createPostgresConfig() {
  cp /etc/postgresql/12/main/postgresql.custom.conf.tmpl /etc/postgresql/12/main/conf.d/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/12/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/12/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql --username ${PGUSER} --host ${PGHOST} --port ${PGPORT} -c "ALTER USER renderer PASSWORD '${PGPASS:-renderer}'"
}

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /data.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    exit 1
fi

if [ "$1" = "import" ]; then
    # Ensure that database directory is in right state
    chown postgres:postgres -R /var/lib/postgresql
    if [ ! -f /var/lib/postgresql/12/main/PG_VERSION ]; then
        sudo -u postgres /usr/lib/postgresql/12/bin/pg_ctl -D /var/lib/postgresql/12/main/ initdb -o "--locale C.UTF-8"
    fi

    # Initialize PostgreSQL
    # createPostgresConfig
    # service postgresql start
    #sudo -u postgres createuser ${PGUSER}
    #sudo -u postgres createdb -E UTF8 -O ${PGUSER} gis
    sudo -u postgres psql -d gis -U ${PGUSER} -h ${PGHOST} -p ${PGPORT} -w -c "CREATE EXTENSION postgis;"
    sudo -u postgres psql -d gis -U ${PGUSER} -h ${PGHOST} -p ${PGPORT} -w -c "CREATE EXTENSION hstore;"
    sudo -u postgres psql -d gis -U ${PGUSER} -h ${PGHOST} -p ${PGPORT} -w -c "ALTER TABLE geometry_columns OWNER TO ${PGUSER};"
    sudo -u postgres psql -d gis -U ${PGUSER} -h ${PGHOST} -p ${PGPORT} -w -c "ALTER TABLE spatial_ref_sys OWNER TO ${PGUSER};"
    # setPostgresPassword

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "$DOWNLOAD_PBF" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget -nv "$DOWNLOAD_PBF" -O /data.osm.pbf
        if [ -n "$DOWNLOAD_POLY" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget -nv "$DOWNLOAD_POLY" -O /data.poly
        fi
    fi

    if [ "$UPDATES" = "enabled" ]; then
        # determine and set osmosis_replication_timestamp (for consecutive updates)
        osmium fileinfo /data.osm.pbf > /var/lib/mod_tile/data.osm.pbf.info
        osmium fileinfo /data.osm.pbf | grep 'osmosis_replication_timestamp=' | cut -b35-44 > /var/lib/mod_tile/replication_timestamp.txt
        REPLICATION_TIMESTAMP=$(cat /var/lib/mod_tile/replication_timestamp.txt)

        # initial setup of osmosis workspace (for consecutive updates)
        sudo -u renderer openstreetmap-tiles-update-expire $REPLICATION_TIMESTAMP
    fi

    # copy polygon file if available
    if [ -f /data.poly ]; then
        sudo -u renderer cp /data.poly /var/lib/mod_tile/data.poly
    fi

    # Import data
    sudo -u postgres osm2pgsql -d gis --username ${PGUSER} --host ${PGHOST} --port ${PGPORT} --create --slim -G --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto/openstreetmap_carto.lua --number-processes ${THREADS:-4} -S /home/renderer/src/openstreetmap-carto/openstreetmap-carto.style /data.osm.pbf ${OSM2PGSQL_EXTRA_ARGS}

    # Create indexes
    #sudo -u postgres psql -d gis -f indexes.sql

    # Register that data has changed for mod_tile caching purposes
    touch /var/lib/mod_tile/planet-import-complete

    #service postgresql stop
    exit 0
fi

if [ "$1" = "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    # Fix postgres data privileges
    #chown postgres:postgres /var/lib/postgresql -R

    # Configure Apache CORS
    if [ "$ALLOW_CORS" == "enabled" ] || [ "$ALLOW_CORS" == "1" ]; then
        echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    fi

    # Initialize PostgreSQL and Apache
    #createPostgresConfig
    #service postgresql start
    service apache2 restart
    #setPostgresPassword

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /usr/local/etc/renderd.conf

    # start cron job to trigger consecutive updates
    if [ "$UPDATES" = "enabled" ] || [ "$UPDATES" = "1" ]; then
      /etc/init.d/cron start
    fi

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf &
    child=$!
    wait "$child"

    #service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
