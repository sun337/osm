FROM overv/openstreetmap-tile-server

COPY project.mml /home/renderer/src/openstreetmap-carto/
RUN chmod +x /home/renderer/src/openstreetmap-carto/project.mml \
 && cd /home/renderer/src/openstreetmap-carto \
 && sed -i "/host/ s/\"host\"/\"${PGHOST}\"/" /home/renderer/src/openstreetmap-carto/project.mml \
 && carto project.mml > mapnik.xml \
 && scripts/get-shapefiles.py

COPY openstreetmap_carto.lua /home/renderer/src/openstreetmap-carto/
RUN chmod +x /home/renderer/src/openstreetmap-carto/openstreetmap_carto.lua

COPY run.sh /run.sh
RUN chmod +x /run.sh
EXPOSE 80