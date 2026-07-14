#!/usr/bin/env python3
"""Emulate iPhone GPS Bridge by streaming a moving GPS fix over TCP."""

import argparse
import asyncio
import json
import math
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone


EARTH_RADIUS_METERS = 6_371_000.0
KILOMETERS_PER_HOUR_TO_METERS_PER_SECOND = 1.0 / 3.6
METERS_PER_SECOND_TO_KNOTS = 1.9438444924406
DEFAULT_ROUTING_URL = "https://routing.openstreetmap.de/routed-car"
USER_AGENT = "iPhoneGPSBridge-GPSEmulator/1.0"


@dataclass
class Position:
    latitude: float
    longitude: float


def move(position: Position, distance_meters: float, bearing_degrees: float) -> Position:
    """Return a point reached along a great-circle path."""
    angular_distance = distance_meters / EARTH_RADIUS_METERS
    bearing = math.radians(bearing_degrees)
    latitude = math.radians(position.latitude)
    longitude = math.radians(position.longitude)

    new_latitude = math.asin(
        math.sin(latitude) * math.cos(angular_distance)
        + math.cos(latitude) * math.sin(angular_distance) * math.cos(bearing)
    )
    new_longitude = longitude + math.atan2(
        math.sin(bearing) * math.sin(angular_distance) * math.cos(latitude),
        math.cos(angular_distance) - math.sin(latitude) * math.sin(new_latitude),
    )

    # Normalize longitude to [-180, 180).
    new_longitude = (new_longitude + math.pi) % (2.0 * math.pi) - math.pi
    return Position(math.degrees(new_latitude), math.degrees(new_longitude))


def distance_between(start: Position, end: Position) -> float:
    latitude_delta = math.radians(end.latitude - start.latitude)
    longitude_delta = math.radians(end.longitude - start.longitude)
    start_latitude = math.radians(start.latitude)
    end_latitude = math.radians(end.latitude)
    haversine = (
        math.sin(latitude_delta / 2.0) ** 2
        + math.cos(start_latitude)
        * math.cos(end_latitude)
        * math.sin(longitude_delta / 2.0) ** 2
    )
    return 2.0 * EARTH_RADIUS_METERS * math.asin(min(1.0, math.sqrt(haversine)))


def bearing_between(start: Position, end: Position) -> float:
    start_latitude = math.radians(start.latitude)
    end_latitude = math.radians(end.latitude)
    longitude_delta = math.radians(end.longitude - start.longitude)
    x = math.sin(longitude_delta) * math.cos(end_latitude)
    y = (
        math.cos(start_latitude) * math.sin(end_latitude)
        - math.sin(start_latitude)
        * math.cos(end_latitude)
        * math.cos(longitude_delta)
    )
    return math.degrees(math.atan2(x, y)) % 360.0


def fetch_driving_route(
    start: Position,
    destination: Position,
    routing_url: str,
) -> tuple[list[Position], float]:
    coordinates = (
        f"{start.longitude:.8f},{start.latitude:.8f};"
        f"{destination.longitude:.8f},{destination.latitude:.8f}"
    )
    query = urllib.parse.urlencode({"overview": "full", "geometries": "geojson"})
    url = f"{routing_url.rstrip('/')}/route/v1/driving/{coordinates}?{query}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            result = json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(f"routing request failed: {error}") from error

    if result.get("code") != "Ok" or not result.get("routes"):
        message = result.get("message") or result.get("code") or "no route found"
        raise RuntimeError(f"routing service returned: {message}")

    route = result["routes"][0]
    raw_coordinates = route.get("geometry", {}).get("coordinates", [])
    if len(raw_coordinates) < 2:
        raise RuntimeError("routing service returned no usable route geometry")

    positions = [
        Position(float(latitude), float(longitude))
        for longitude, latitude in raw_coordinates
    ]
    return positions, float(route.get("distance", 0.0))


class RouteFollower:
    def __init__(self, positions: list[Position]) -> None:
        self.positions = positions
        self.position = positions[0]
        self.next_index = 1
        self.bearing = bearing_between(positions[0], positions[1])
        self.finished = False

    def advance(self, distance_meters: float) -> tuple[Position, float, bool]:
        while distance_meters > 0.0 and self.next_index < len(self.positions):
            target = self.positions[self.next_index]
            segment_distance = distance_between(self.position, target)
            if segment_distance < 0.01:
                self.position = target
                self.next_index += 1
                continue

            self.bearing = bearing_between(self.position, target)
            if distance_meters < segment_distance:
                self.position = move(self.position, distance_meters, self.bearing)
                distance_meters = 0.0
            else:
                self.position = target
                self.next_index += 1
                distance_meters -= segment_distance

        self.finished = self.next_index >= len(self.positions)
        return self.position, self.bearing, self.finished


def nmea_coordinate(degrees: float, degree_digits: int) -> tuple[str, str]:
    absolute = abs(degrees)
    whole_degrees = int(absolute)
    minutes = (absolute - whole_degrees) * 60.0
    value = f"{whole_degrees:0{degree_digits}d}{minutes:09.6f}"
    if degree_digits == 2:
        hemisphere = "N" if degrees >= 0 else "S"
    else:
        hemisphere = "E" if degrees >= 0 else "W"
    return value, hemisphere


def nmea_sentence(body: str) -> str:
    checksum = 0
    for byte in body.encode("ascii"):
        checksum ^= byte
    return f"${body}*{checksum:02X}\r\n"


def encode_fix(
    position: Position,
    timestamp: datetime,
    speed_meters_per_second: float,
    bearing_degrees: float,
) -> bytes:
    """Encode one fix in the bridge's JSON + GPRMC + GPGGA format."""
    timestamp = timestamp.astimezone(timezone.utc)
    timestamp_text = timestamp.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    json_record = {
        "altitudeMeters": 0.0,
        "courseDegrees": bearing_degrees,
        "horizontalAccuracyMeters": 5.0,
        "latitude": position.latitude,
        "longitude": position.longitude,
        "speedMetersPerSecond": speed_meters_per_second,
        "timestamp": timestamp_text,
        "type": "location",
        "verticalAccuracyMeters": 5.0,
    }

    time_text = timestamp.strftime("%H%M%S.") + f"{timestamp.microsecond // 10_000:02d}"
    date_text = timestamp.strftime("%d%m%y")
    latitude, north_south = nmea_coordinate(position.latitude, 2)
    longitude, east_west = nmea_coordinate(position.longitude, 3)
    speed_knots = speed_meters_per_second * METERS_PER_SECOND_TO_KNOTS

    rmc = (
        f"GPRMC,{time_text},A,{latitude},{north_south},{longitude},{east_west},"
        f"{speed_knots:.2f},{bearing_degrees:.2f},{date_text},,,A"
    )
    gga = (
        f"GPGGA,{time_text},{latitude},{north_south},{longitude},{east_west},"
        "1,00,1.0,0.0,M,0.0,M,,"
    )

    json_line = json.dumps(json_record, sort_keys=True, separators=(",", ":")) + "\n"
    return (json_line + nmea_sentence(rmc) + nmea_sentence(gga)).encode("ascii")


class GPSEmulator:
    def __init__(
        self,
        position: Position,
        speed_kmh: float,
        bearing: float,
        route: list[Position] | None = None,
    ) -> None:
        self.position = position
        self.speed_meters_per_second = speed_kmh * KILOMETERS_PER_HOUR_TO_METERS_PER_SECOND
        self.bearing = bearing % 360.0
        self.clients: set[asyncio.StreamWriter] = set()
        self.route_follower = RouteFollower(route) if route else None
        if self.route_follower:
            self.position = self.route_follower.position
            self.bearing = self.route_follower.bearing
        self.route_finished = False

    async def accept(self, _reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.clients.add(writer)
        peer = writer.get_extra_info("peername")
        print(f"Client connected: {peer} ({len(self.clients)} total)")
        try:
            await _reader.read()
        finally:
            self.clients.discard(writer)
            writer.close()
            await writer.wait_closed()
            print(f"Client disconnected: {peer} ({len(self.clients)} total)")

    async def broadcast_loop(self) -> None:
        loop = asyncio.get_running_loop()
        previous_update = loop.time()

        while True:
            now = loop.time()
            elapsed = now - previous_update
            previous_update = now
            current_speed = 0.0 if self.route_finished else self.speed_meters_per_second
            if self.route_follower:
                self.position, self.bearing, self.route_finished = self.route_follower.advance(
                    current_speed * elapsed
                )
            else:
                self.position = move(self.position, current_speed * elapsed, self.bearing)
            payload = encode_fix(
                self.position,
                datetime.now(timezone.utc),
                current_speed,
                self.bearing,
            )

            failed: list[asyncio.StreamWriter] = []
            for writer in tuple(self.clients):
                try:
                    writer.write(payload)
                    await writer.drain()
                except (ConnectionError, OSError):
                    failed.append(writer)
            for writer in failed:
                self.clients.discard(writer)
                writer.close()

            await asyncio.sleep(1.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream an emulated moving GPS fix in iPhone GPS Bridge format."
    )
    parser.add_argument("latitude", type=float, help="start latitude in decimal degrees")
    parser.add_argument("longitude", type=float, help="start longitude in decimal degrees")
    parser.add_argument("--speed", type=float, default=50.0, metavar="KM/H", help="speed (default: 50)")
    parser.add_argument("--bearing", type=float, default=45.0, metavar="DEGREES", help="direction clockwise from north (default: 45)")
    parser.add_argument(
        "--destination",
        type=float,
        nargs=2,
        metavar=("LATITUDE", "LONGITUDE"),
        help="destination; follow a driving route instead of a straight line",
    )
    parser.add_argument(
        "--routing-url",
        default=DEFAULT_ROUTING_URL,
        help=f"OSRM server base URL (default: {DEFAULT_ROUTING_URL})",
    )
    parser.add_argument("--host", default="0.0.0.0", help="listen address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=10110, help="TCP port (default: 10110)")
    args = parser.parse_args()

    if not -90.0 <= args.latitude <= 90.0:
        parser.error("latitude must be between -90 and 90")
    if not -180.0 <= args.longitude <= 180.0:
        parser.error("longitude must be between -180 and 180")
    if args.destination:
        destination_latitude, destination_longitude = args.destination
        if not -90.0 <= destination_latitude <= 90.0:
            parser.error("destination latitude must be between -90 and 90")
        if not -180.0 <= destination_longitude <= 180.0:
            parser.error("destination longitude must be between -180 and 180")
    if args.speed < 0.0:
        parser.error("speed cannot be negative")
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    return args


async def run(args: argparse.Namespace) -> None:
    start = Position(args.latitude, args.longitude)
    route = None
    if args.destination:
        destination = Position(*args.destination)
        print("Requesting driving route from OpenStreetMap/OSRM...")
        route, route_distance = await asyncio.to_thread(
            fetch_driving_route,
            start,
            destination,
            args.routing_url,
        )
        print(f"Loaded {route_distance / 1000.0:.2f} km street route ({len(route)} points)")

    emulator = GPSEmulator(start, args.speed, args.bearing, route)
    server = await asyncio.start_server(emulator.accept, args.host, args.port)
    addresses = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
    print(
        f"Listening on {addresses}; start={args.latitude:.6f},{args.longitude:.6f}, "
        f"speed={args.speed:g} km/h, bearing={emulator.bearing:g} degrees"
    )

    broadcast_task = asyncio.create_task(emulator.broadcast_loop())
    try:
        async with server:
            await server.serve_forever()
    finally:
        broadcast_task.cancel()
        await asyncio.gather(broadcast_task, return_exceptions=True)


def main() -> None:
    args = parse_args()
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\nStopped")
    except (OSError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
