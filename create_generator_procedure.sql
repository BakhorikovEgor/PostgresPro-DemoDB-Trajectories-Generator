CREATE OR REPLACE PROCEDURE bookings.generate_all_trajectories()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE bookings.flight_trajectories;

    INSERT INTO bookings.flight_trajectories (flight_id, point_time, longitude, latitude, altitude, geom)
    WITH constants AS (
        SELECT
            0.033 AS grad_climb,
            0.052 AS grad_descent,
            11000.0 AS max_ceiling,
            50000 AS segment_step_m
    ),
    flight_basics AS (
        SELECT
            f.flight_id, f.scheduled_departure,
            (f.scheduled_arrival - f.scheduled_departure) AS flight_duration,
            dep.coordinates[0] AS dep_lon, dep.coordinates[1] AS dep_lat,
            arr.coordinates[0] AS arr_lon, arr.coordinates[1] AS arr_lat,
            ST_Distance(
                ST_SetSRID(ST_MakePoint(dep.coordinates[0], dep.coordinates[1]), 4326)::geography,
                ST_SetSRID(ST_MakePoint(arr.coordinates[0], arr.coordinates[1]), 4326)::geography
            ) AS dist_m
        FROM bookings.flights f
        JOIN bookings.routes r ON f.route_no = r.route_no
        JOIN bookings.airports_data dep ON r.departure_airport = dep.airport_code
        JOIN bookings.airports_data arr ON r.arrival_airport = arr.airport_code
        WHERE f.scheduled_arrival > f.scheduled_departure
    ),
    physics AS (
        SELECT fb.*, c.grad_climb, c.grad_descent, c.max_ceiling, c.segment_step_m,
            LEAST(c.max_ceiling, fb.dist_m / ((1.0/c.grad_climb) + (1.0/c.grad_descent))) AS h_cruise
        FROM flight_basics fb
        CROSS JOIN constants c
    ),
    kinematics AS (
        SELECT *,
            (h_cruise / grad_climb) AS d_toc,
            (dist_m - (h_cruise / grad_descent)) AS d_tod
        FROM physics
    ),
    arcs AS (
        SELECT flight_id, scheduled_departure, flight_duration, dist_m,
            h_cruise, grad_climb, grad_descent, d_toc, d_tod,
            segment_step_m,
            ST_Segmentize(
                ST_MakeLine(
                    ST_SetSRID(ST_MakePoint(dep_lon, dep_lat), 4326),
                    ST_SetSRID(ST_MakePoint(arr_lon, arr_lat), 4326)
                )::geography, segment_step_m
            )::geometry AS curved_line
        FROM kinematics
    ),
    points AS (
        SELECT flight_id, scheduled_departure, flight_duration, dist_m,
            h_cruise, grad_climb, grad_descent, d_toc, d_tod,
            (ST_DumpPoints(curved_line)).path[1] AS point_order,
            ST_NumPoints(curved_line) AS total_points,
            (ST_DumpPoints(curved_line)).geom AS pt
        FROM arcs
    ),
    profile_calc AS (
        SELECT flight_id, scheduled_departure, flight_duration, pt, dist_m,
            h_cruise, grad_climb, grad_descent, d_toc, d_tod,
            (((point_order - 1)::float / NULLIF(total_points - 1, 0)) * dist_m) AS current_d
        FROM points
    )
    SELECT flight_id,
        scheduled_departure + (flight_duration * (current_d / NULLIF(dist_m, 0))),
        ST_X(pt), ST_Y(pt),
        ROUND(
            CASE
                WHEN current_d <= d_toc THEN current_d * grad_climb
                WHEN current_d >= d_tod THEN (dist_m - current_d) * grad_descent
                ELSE h_cruise
            END::numeric, 0
        ) AS altitude,
        ST_SetSRID(ST_MakePoint(ST_X(pt), ST_Y(pt),
            CASE
                WHEN current_d <= d_toc THEN current_d * grad_climb
                WHEN current_d >= d_tod THEN (dist_m - current_d) * grad_descent
                ELSE h_cruise
            END
        ), 4326) AS geom
    FROM profile_calc;
END;
$$;