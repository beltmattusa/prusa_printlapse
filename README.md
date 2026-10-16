# printlapse

Automatic print timelapses for a Prusa printer with a Buddy3D camera, recorded by a small Docker container.

The container polls the printer through PrusaLink. While a print runs, it grabs a frame from the camera's local RTSP stream every 10 seconds. When the print ends, it stitches the frames into an MP4 in `timelapses/` and deletes them. Nothing goes through Prusa Connect or the cloud.

## Requirements

- Prusa printer with PrusaLink running current firmware
- Buddy3D camera on the same network as the Docker host
- Docker with Compose (any Linux host, a Synology NAS with Container Manager, etc.)

## Before you start

1. **Camera URL.** Open `rtsp://<camera-ip>/live` in VLC (Media > Open Network Stream). If it plays, the container can read it.
2. **PrusaLink password.** On the printer: Settings > Network > PrusaLink. The username is `maker`; the password may be labelled "API key". Use the PrusaLink key, not the Prusa Connect key.
3. **Printer URL.** `http://<printer-ip>`. Logging in there with `maker` and the key should show the PrusaLink dashboard.

Give the printer and camera DHCP reservations so their addresses don't change.

## Quick start (Docker Compose)

```bash
git clone https://github.com/beltmattusa/prusa_printlapse.git
cd prusa_printlapse
cp .env.example .env
nano .env                 # set CAMERA_URL, PRINTER_URL, PRUSALINK_PASS
docker compose up -d
docker compose logs -f
```

The first start takes about a minute while the container installs ffmpeg. Then the log shows:

```
Watching http://<printer-ip>, camera rtsp://<camera-ip>/live, one frame every 10s
```

Start a print. Within about 10 seconds you'll see `Print started, recording to /frames/...`. When the print ends, the MP4 appears in `timelapses/`, named by start time and print file, e.g. `2026-10-15_2100_Benchy.mp4`.

## Without Compose

```bash
docker run -d --name printlapse --restart unless-stopped \
  --env-file .env \
  -v "$PWD/printlapse.sh:/app/printlapse.sh:ro" \
  -v "$PWD/frames:/frames" \
  -v "$PWD/timelapses:/output" \
  alpine:3.20 \
  sh -c "apk add --no-cache bash ffmpeg curl jq tzdata coreutils >/dev/null && exec bash /app/printlapse.sh"
```

## Configuration

All settings live in `.env`. After changing it, run `docker compose up -d --force-recreate`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `CAMERA_URL` | required | Camera RTSP stream, `rtsp://<camera-ip>/live` |
| `PRINTER_URL` | required | PrusaLink address, `http://<printer-ip>` |
| `PRUSALINK_USER` | `maker` | PrusaLink username |
| `PRUSALINK_PASS` | required | PrusaLink password / API key |
| `TZ` | UTC | Time zone for file names and logs |
| `INTERVAL` | 10 | Seconds between frames |
| `FPS` | 30 | Playback frame rate (10 s x 30 fps = 5 min of printing per second of video) |
| `HOLD_END` | 3 | Seconds to hold the final frame |
| `KEEP_FRAMES` | false | Keep the JPGs in `timelapses/frames/` |
| `OFFLINE_LIMIT` | 600 | Seconds the printer can be unreachable before the recording is closed |

To store videos somewhere else, change `./timelapses` in `docker-compose.yml` to an absolute path.

## Common commands

```bash
docker compose logs -f                      # follow the log
docker compose restart                      # restart (avoid during a print)
docker compose down                         # stop and remove
git pull && docker compose up -d --force-recreate   # update

# Rebuild a video from a leftover frames folder
docker exec printlapse bash /app/printlapse.sh stitch /frames/<folder>
```

Files in `frames/` and `timelapses/` are written by root inside the container. On a Linux host, use `sudo` to delete them or `chown` the folders.

## Synology

1. Copy the repo contents to `/volume1/docker/printlapse` (`notify.sh` expects that path; pass a different `timelapses` folder as its first argument if you use another). The `frames` and `timelapses` folders must exist; Synology won't create bind-mount paths and fails with `Bind mount failed ... does not exist`.
2. Create `.env` from `.env.example`. File Station hides dotfiles, so it may not show after upload.
3. Container Manager > Project > Create, path `/docker/printlapse`, use the existing `docker-compose.yml`, build.
4. Logs: Container > printlapse > Details > Log.

### Email when a video is ready

`notify.sh` runs on the NAS and uses DSM's own email settings (Control Panel > Notification > Email). Create a task in Control Panel > Task Scheduler > Create > Scheduled Task > User-defined script:

| Setting | Value |
| --- | --- |
| User | root |
| Schedule | Daily, every 5 minutes, 00:00 to 23:55 |
| Send run details by email | On |
| Only when the script terminates abnormally | On |
| Command | `bash /volume1/docker/printlapse/notify.sh` |

The script exits 1 only when it finds a new video, so DSM emails just those runs, with a share link in the body. The subject says the task ended abnormally; that's expected. Reported videos are listed in `timelapses/.notified`; delete it to report everything again.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `CAMERA_URL is required` | `.env` is missing or not filled in |
| `Frame grab failed` repeating | The host can't read the stream. Test `CAMERA_URL` in VLC from the same network |
| No `Print started` during a print | Wrong `PRINTER_URL` or password. Log in at the printer's IP with `maker` and the key |
| One print split into two videos | The container restarted mid-print |
| Video ends early | Printer was unreachable for `OFFLINE_LIMIT` seconds |
| Email shows a NAS path, not a link | `synowebapi` couldn't create a share link on this DSM version |

## Limitations

- Frames are taken on a timer, not per layer, so the print head moves between frames.
- The RTSP stream is unencrypted; keep it on your local network.
