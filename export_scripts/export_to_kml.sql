WITH random_flights AS (
    SELECT f.flight_id
    FROM bookings.flights f
    JOIN bookings.routes r ON f.route_no = r.route_no
    JOIN bookings.airports_data dep ON r.departure_airport = dep.airport_code
    JOIN bookings.airports_data arr ON r.arrival_airport = arr.airport_code
    WHERE f.scheduled_arrival > f.scheduled_departure
    ORDER BY random()
    LIMIT 200
),
lines AS (
    SELECT t.flight_id, ST_MakeLine(t.geom ORDER BY t.point_time) as geom3d
    FROM bookings.flight_trajectories t
    JOIN random_flights f ON t.flight_id = f.flight_id
    GROUP BY t.flight_id
)
SELECT 
  '<?xml version=\"1.0\" encoding=\"UTF-8\"?>
   <kml xmlns=\"http://www.opengis.net/kml/2.2\">
   <Document>
   <name>200 Random Flights (Realistic)</name>' || 
  string_agg(
    '<Placemark>
       <name>Flight ' || flight_id || '</name>
       <Style>
         <LineStyle>
           <color>ff00ffff</color>
           <width>3</width>
         </LineStyle>
       </Style>
       ' || REPLACE(ST_AsKML(geom3d), '<LineString>', '<LineString><altitudeMode>absolute</altitudeMode>') || '
     </Placemark>', 
    ''
  ) || 
  '</Document></kml>'
FROM lines;