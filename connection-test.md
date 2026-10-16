## Testing the connection

Run these inside the container to check it can reach the printer and camera. They read `CAMERA_URL`, `PRINTER_URL` and the PrusaLink login from your `.env`, so nothing needs editing.

Open a shell in the container:

```bash
docker exec -it printlapse bash
```

On Synology: Container Manager > Container > printlapse > Terminal > Create > bash.

Then paste:

```bash
cam=${CAMERA_URL#*://}; cam=${cam%%/*}; cam=${cam%%:*}
prn=${PRINTER_URL#*://}; prn=${prn%%/*}; prn=${prn%%:*}

echo "== Printer ($prn)"; ping -c 3 "$prn"
echo "== Camera ($cam)";  ping -c 3 "$cam"

echo "== PrusaLink login"
curl -fsS -m 5 --digest -u "${PRUSALINK_USER:-maker}:$PRUSALINK_PASS" \
  "${PRINTER_URL%/}/api/v1/status" | jq -r '.printer.state'

echo "== Camera frame"
ffmpeg -loglevel error -rtsp_transport tcp -i "$CAMERA_URL" \
  -frames:v 1 -update 1 -y /frames/test.jpg && ls -l /frames/test.jpg && rm /frames/test.jpg
```

A healthy setup shows replies from both pings, a printer state such as `IDLE` or `PRINTING`, and a `test.jpg` of roughly 100–200 KB.

| Result | Meaning | Fix |
| --- | --- | --- |
| Printer ping fails | The container can't reach the network | Restart the container or project |
| Camera ping fails with `Host is unreachable` | The camera is off the network or has a new IP | Reboot the camera; check its IP in the Prusa app and set a DHCP reservation |
| Camera plays in VLC on another device but the ping above fails | The network isn't passing traffic between the Docker host and the camera | Reboot the camera; if it keeps happening, check the router for client isolation or a separate IoT/guest network |
| PrusaLink step prints an error | Wrong `PRINTER_URL` or password | Log in at the printer's address with `maker` and the API key |
| Camera frame step fails but ping works | The RTSP stream isn't available | Check `CAMERA_URL` ends in `/live`; reboot the camera |
