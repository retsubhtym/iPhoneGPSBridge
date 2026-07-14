# iPhone GPS Bridge

iPhone GPS Bridge exposes the latest iPhone location as a newline-delimited TCP
stream. It emits one JSON record followed by two NMEA 0183 sentences every
second, even when the coordinates have not changed.

## Install and prepare the iPhone app

The app must be installed on the iPhone before either laptop setup below can be
used. Building and signing an iOS app requires a Mac with a version of Xcode
that supports the iOS version on the phone; Ubuntu cannot build or install this
Xcode project by itself.

1. On the Mac, open `iPhoneGPSBridge.xcodeproj` in Xcode.
2. Select the **iPhoneGPSBridge** target, open **Signing & Capabilities**, select
   your development team, and change the bundle identifier if Xcode reports
   that the existing one is unavailable.
3. Connect and unlock the iPhone, tap **Trust** when prompted, select it as the
   Xcode run destination, and run the app. If iOS requests Developer Mode,
   enable it under **Settings > Privacy & Security > Developer Mode**, restart
   the phone, and run the app again.
4. In iPhone GPS Bridge, tap **Start GPS Bridge**, grant location access, and
   wait for **Status** to show `Listening`.
5. For streaming while the app is not in the foreground, tap **Request Always
   Location Access** and approve the subsequent iOS prompt. iOS may offer the
   Always upgrade only after the app has first received While Using access.

Leave the bridge running. iOS shows its background-location indicator while
the app is using location in the background. The stream stops after the app is
force-quit and its TCP connections must be recreated after the app or USB link
is interrupted.

## Use on macOS over USB

Install the USB communication tools with Homebrew:

```bash
brew install libimobiledevice
```

Connect and unlock the iPhone and accept **Trust This Computer** on the phone.
Verify that the device is visible:

```bash
idevice_id -l
```

If this prints no device identifier, reconnect the cable, unlock the phone, and
confirm the trust prompt. Check which `iproxy` command syntax your installed
version uses:

```bash
iproxy --help
```

If its usage line shows `LOCAL_PORT:DEVICE_PORT` (current releases), start the
USB tunnel in Terminal 1 with:

```bash
iproxy 10110:10110
```

Older releases use two positional port arguments instead:

```bash
iproxy 10110 10110
```

`iproxy` forwards Mac port 10110 to the app's port 10110 through usbmuxd. It
does not print the GPS data itself. In Terminal 2, test the stream:

```bash
nc 127.0.0.1 10110
```

After the app has a location fix, JSON, `GPRMC`, and `GPGGA` lines should appear
approximately once per second. Press Control-C to stop `nc`. Applications that
accept a TCP GPS source can now use host `127.0.0.1` and port `10110` directly.

### Optional macOS pseudo-serial device

For software that requires a device path, install `socat`:

```bash
brew install socat
```

Keep `iproxy` running, then run this in another terminal:

```bash
socat PTY,link=/tmp/iphone-gps,raw,echo=0 TCP:127.0.0.1:10110
```

Keep `socat` running and configure the consuming program to open
`/tmp/iphone-gps`. Test it from another terminal with:

```bash
cat /tmp/iphone-gps
```

The link is temporary and is recreated each time `socat` starts. Only use this
adapter when a program cannot consume the TCP stream directly.

## Use on Ubuntu over USB

The app must already be installed on the iPhone as described above. On Ubuntu,
install usbmuxd, the libimobiledevice utilities, `iproxy`, and the optional
pseudo-terminal/GPS tools:

```bash
sudo apt update
sudo apt install usbmuxd libimobiledevice-utils libusbmuxd-tools socat gpsd gpsd-clients
```

On Ubuntu releases where `libusbmuxd-tools` is unavailable, search for the
package containing `iproxy`:

```bash
apt search iproxy
```

Connect and unlock the iPhone, accept **Trust This Computer**, then pair and
verify it:

```bash
idevicepair pair
idevice_id -l
```

Keep the phone unlocked for the initial pairing. Run `iproxy --help` to check
the syntax supplied by the Ubuntu release. For a version whose usage line shows
`LOCAL_PORT:DEVICE_PORT`, start the tunnel in Terminal 1 with:

```bash
iproxy 10110:10110
```

For an older version that shows separate local and device port arguments, use:

```bash
iproxy 10110 10110
```

In Terminal 2, verify the app's stream:

```bash
nc 127.0.0.1 10110
```

Applications that accept a TCP source should connect directly to
`127.0.0.1:10110`.

### Optional Ubuntu pseudo-serial device

Keep `iproxy` running and create a device-like path with:

```bash
sudo socat PTY,link=/dev/iphone-gps,raw,echo=0,mode=666 TCP:127.0.0.1:10110
```

Keep `socat` running. In another terminal, verify the stream:

```bash
cat /dev/iphone-gps
```

The `/dev/iphone-gps` link exists only while `socat` is running. The permissive
mode is convenient for a temporary local setup; use an appropriate group and a
more restrictive mode for a shared or permanent system.

### Optional Ubuntu gpsd integration

First stop the socket-activated system instance so it does not compete for the
device or TCP port, then start a foreground gpsd process:

```bash
sudo systemctl stop gpsd.socket gpsd.service 2>/dev/null || true
sudo gpsd -N -n -D 3 /dev/iphone-gps
```

Keep `iproxy`, `socat`, and `gpsd` running in their respective terminals. Check
gpsd from another terminal:

```bash
cgps
```

or inspect its JSON output:

```bash
gpspipe -w
```

gpsd listens on `127.0.0.1:2947` by default, allowing multiple local programs
to share the location. The bridge interleaves its own JSON records with NMEA;
gpsd ignores the non-NMEA records and consumes the `GPRMC`/`GPGGA` sentences.

For example, a Python program can read gpsd's normalized TPV records:

```python
import json
import socket

with socket.create_connection(("127.0.0.1", 2947), timeout=5) as sock:
    sock.sendall(b'?WATCH={"enable":true,"json":true}\n')
    with sock.makefile("r", encoding="ascii", errors="replace") as stream:
        for line in stream:
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("class") == "TPV":
                latitude = message.get("lat")
                longitude = message.get("lon")
                if latitude is not None and longitude is not None:
                    print(f"Latitude: {latitude:.8f}, Longitude: {longitude:.8f}")
```

## Connection troubleshooting

- `Address already in use` from `iproxy` means another process is using local
  port 10110. Stop the old `iproxy` process or choose another local port, for
  example `iproxy 10111:10110` (or `iproxy 10111 10110` with the older syntax),
  and connect to `127.0.0.1:10111`.
- A successful `iproxy` connection but no records usually means the bridge is
  stopped, its status is not `Listening`, location permission was denied, or
  the iPhone has not obtained its first fix.
- If several iOS devices are attached, get the desired identifier from
  `idevice_id -l` and run `iproxy -u DEVICE_UDID 10110:10110`. With an older
  `iproxy`, check `iproxy --help`; some versions use
  `iproxy 10110 10110 DEVICE_UDID` instead.
- If the stream stops after locking the phone, grant Always location access and
  ensure the bridge was not force-quit. iOS still controls process lifetime, so
  consumers should reconnect after interruptions.

The recommended process chain is:

```text
iPhone GPS Bridge -> iproxy over USB -> TCP consumer
                                      -> socat PTY -> gpsd -> applications
```

## Alternative: USB Personal Hotspot

Instead of `iproxy`, the app can be reached over the network interface created
by iPhone Personal Hotspot. On the iPhone, enable **Settings > Personal Hotspot
> Allow Others to Join**, connect it by USB, and start the bridge. The app still
listens on port 10110.

Do not hard-code a commonly seen address such as `172.20.10.1`; determine the
active interface and route on the laptop. On macOS, inspect:

```bash
route -n get default
```

On Ubuntu, inspect:

```bash
ip route
```

Then connect `nc` or the consuming application to the iPhone address on port
10110. Ubuntu USB tethering support depends on the distribution's `ipheth`,
usbmuxd, and NetworkManager configuration. For a predictable USB-only data
path that does not enable tethering, use `iproxy`.

## Limitations

- Connecting the cable alone does not expose an iPhone as a USB GPS, serial,
  NMEA, or `/dev/tty*` device. This app must be running and exporting location.
- macOS Core Location does not automatically adopt the connected iPhone as the
  Mac's system location source.
- Core Location reports fused location, which is not necessarily a raw GNSS
  measurement.
- The generated NMEA timestamps are not PPS-accurate, and the app does not
  provide RTK corrections or raw satellite measurements. Use a dedicated GNSS
  receiver for precision timing, survey, RTK, or sub-metre positioning.

## Transport and framing

- Protocol: raw TCP; this is not HTTP or WebSocket.
- Encoding: UTF-8. NMEA records contain ASCII characters only.
- Framing: one record per line.
- JSON ends with `\n`; NMEA sentences end with `\r\n`.
- No request, handshake, or subscription message is required after connecting.
- A newly connected client receives the cached fix on the next one-second tick.
- Multiple TCP clients can connect at the same time.

TCP does not preserve message boundaries. Consumers must buffer received bytes
and split complete records on `\n`; they must not assume that one socket read is
one record. Remove a trailing `\r` before parsing an NMEA line.

If the connection closes, reconnect to the same host and port. The location
timestamp may remain unchanged while a cached stationary fix is being resent.

The stream continues while the app is in the background as long as the bridge
is running and iOS keeps the app's location session active. It cannot continue
after the user force-quits the app, and the TCP connection is lost if iOS
terminates the process or the USB connection is interrupted.

## Stream example

Each one-second batch has this shape:

```text
{"altitudeMeters":10.0,"courseDegrees":90.0,"horizontalAccuracyMeters":5.0,"latitude":0.0,"longitude":0.0,"speedMetersPerSecond":0.2,"timestamp":"<ISO-8601 timestamp>","type":"location","verticalAccuracyMeters":3.0}
$GPRMC,<UTC time>,A,0000.000000,N,00000.000000,E,0.39,90.00,<UTC date>,,,A*XX
$GPGGA,<UTC time>,0000.000000,N,00000.000000,E,1,00,1.0,10.0,M,0.0,M,,*XX
```

These are synthetic placeholder values. The example NMEA checksums are shown
as `XX`; real output contains the computed two-digit hexadecimal checksum.

## JSON record

JSON is the recommended format for application integration.

| Field | Type | Unit and meaning |
| --- | --- | --- |
| `type` | string | Always `location`. |
| `timestamp` | string | UTC ISO 8601 timestamp of the iOS location measurement. |
| `latitude` | number | Decimal degrees; north is positive. |
| `longitude` | number | Decimal degrees; east is positive. |
| `horizontalAccuracyMeters` | number | Estimated horizontal radius in metres. |
| `altitudeMeters` | number, optional | Altitude above mean sea level in metres. |
| `verticalAccuracyMeters` | number, optional | Estimated vertical accuracy in metres. |
| `speedMetersPerSecond` | number, optional | Ground speed in metres per second. |
| `courseDegrees` | number, optional | Direction of travel in degrees clockwise from true north. |

Optional fields are omitted when iOS reports that value as unavailable. A
repeated record retains the measurement timestamp; receipt time should be
recorded separately by the consuming application if needed.

## NMEA records

The bridge emits these NMEA 0183-style sentences after each JSON record:

- `GPRMC`: UTC time/date, validity, latitude, longitude, speed in knots, and
  course in degrees.
- `GPGGA`: UTC time, latitude, longitude, fix quality, approximate HDOP, and
  altitude in metres.

Latitude uses `ddmm.mmmmmm` plus `N` or `S`. Longitude uses `dddmm.mmmmmm` plus
`E` or `W`. Each sentence starts with `$` and ends with `*HH`, where `HH` is the
XOR checksum of the bytes between `$` and `*`.

The GGA satellite count is currently reported as `00`, and HDOP is approximated
from Core Location horizontal accuracy. Use JSON when those NMEA fields matter.

## Minimal consumer logic

```python
import json
import socket

with socket.create_connection(("127.0.0.1", 10110)) as sock:
    with sock.makefile("r", encoding="utf-8", errors="replace") as records:
        for raw_line in records:
            line = raw_line.rstrip("\r\n")
            if line.startswith("{"):
                location = json.loads(line)
                print(location["latitude"], location["longitude"])
            elif line.startswith("$"):
                print("NMEA:", line)
```

Production consumers should catch connection and parsing errors, reconnect with
backoff, validate `type == "location"`, and decide how old a measurement may be
by comparing `timestamp` with the current time.
