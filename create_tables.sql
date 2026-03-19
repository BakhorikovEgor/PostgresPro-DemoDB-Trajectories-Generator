CREATE EXTENSION IF NOT EXISTS postgis;

CREATE UNLOGGED TABLE bookings.flight_trajectories (
    id SERIAL PRIMARY KEY,
    flight_id INTEGER NOT NULL,
    point_time TIMESTAMP WITH TIME ZONE NOT NULL,
    longitude NUMERIC NOT NULL,
    latitude NUMERIC NOT NULL,
    altitude NUMERIC NOT NULL,
    geom geometry(PointZ, 4326),

    CONSTRAINT fk_trajectory_flight
        FOREIGN KEY (flight_id)
        REFERENCES bookings.flights (flight_id)
        ON DELETE CASCADE
);

CREATE INDEX idx_flight_trajectories_flight_id
    ON bookings.flight_trajectories (flight_id);

CREATE INDEX idx_flight_trajectories_geom
    ON bookings.flight_trajectories USING GIST (geom);