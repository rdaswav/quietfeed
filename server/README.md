# Rules server

A tiny nginx container on the NAS that serves `rulepack.json` on the home network.
The app fetches `http://your-server:8787/rulepack.json` (change it in Settings).
The pack is declarative JSON only, never code, because it travels over plain HTTP.

## One-time setup (run by hand, not by the build loop)

1. Check that port 8787 is free:

   ```
   ssh nas "docker ps --format '{{.Names}} {{.Ports}}'"
   ```

   If something already uses 8787, pick another port and change it here, in
   `docker-compose.yml`, and in the app's Settings.

2. Create the folders and copy the nginx config (scp is disabled, so use tar):

   ```
   ssh nas "mkdir -p /volume1/docker/quietfeed/rules"
   tar -C server -cf - nginx.conf | ssh nas "tar -C /volume1/docker/quietfeed -xf -"
   ```

3. Create the container:

   ```
   ssh nas "docker run -d --name quietfeed-rules --restart unless-stopped \
     -p 8787:80 \
     -v /volume1/docker/quietfeed/rules:/usr/share/nginx/html:ro \
     -v /volume1/docker/quietfeed/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
     nginx:alpine"
   ```

   `docker-compose.yml` describes the same container if you prefer Compose.

4. Deploy the first pack: `./scripts/deploy-rules.sh`

## Updating rules

Edit `rules/rulepack.json`, bump `packVersion`, run `./scripts/deploy-rules.sh`
(use `--dry-run` to see the command first), then "Check now" in the app's Settings.

## Checks

- `curl http://your-server:8787/rulepack.json` returns the pack.
- Any other path returns 404.
