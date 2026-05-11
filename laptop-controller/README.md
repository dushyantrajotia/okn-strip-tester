Production hosting checklist and steps

Goal
- Provide a stable, permanent hosted backend + frontend for the doctor to use daily.

Recommended approaches (ordered by long-term reliability)

1) Managed cloud (recommended)
- Use Railway / Render / Heroku to host the Node backend.
- Use Vercel to host the frontend (already done).
- Add a custom domain (example: controller.example.com) and point DNS to the provider. Ensure SSL is enabled.

High-level steps for managed cloud
1. Put the `laptop-controller` folder into a Git repo and push to GitHub.
2. In Railway/Render/Heroku, create a new service and connect the GitHub repo.
   - Set the build/start command (the project already has `npm start` and a `Procfile`).
   - Ensure `PORT` is used by the server (already implemented).
3. Deploy and confirm the service is `Online`.
4. Add a custom domain in the cloud provider dashboard.
   - Follow provider instructions: create an A or CNAME record at your DNS registrar pointing to the provider.
   - Wait for DNS propagation. Confirm `nslookup controller.example.com` returns an IP.
5. Update clients to use `wss://controller.example.com/ws` (frontend and Flutter app).

Notes about Railway DNS issues we saw
- Railway assigned a `.up.railway.app` domain but your local network DNS refused lookup. This can be caused by local network DNS caching or firewall rules.
- If using Railway, ensure the service is deployed from a repo (recommended) so DNS provisioning completes.

2) LAN + simple share (fast, not remote)
- Keep server running on laptop and give the doctor the laptop LAN IP (e.g. `http://10.142.71.198:8080`).
- Use `start-server.bat` to start the server. Create a desktop shortcut for non‑tech users.
- Pros: instant. Cons: requires laptop and same network.

3) Temporary public tunnel (ngrok) — quick remote sharing
- Install ngrok, authenticate, then run `ngrok http 8080` and share the generated HTTPS URL.
- Pros: easy to set up and share immediately. Cons: not ideal for permanent production (limits and token setup required).

How to update clients after you have a production domain
- Frontend (Vercel): open `public/app.js` and ensure `wsUrlFromHost` will return `wss://your-domain/ws` (the code already appends `/ws`). Redeploy Vercel after updating default host if desired.
- Flutter app: update `_socketUrl` in `android-app/lib/main.dart` to:

  `String _socketUrl = 'wss://controller.example.com/ws';`

  Then `flutter build apk` / `flutter run` and install on the phone.

Files I added
- `Procfile` — for Heroku/Render
- `start-server.bat` — double‑click to start the server on Windows
- `README.md` — deployment and sharing instructions

If you want, I can next:
- Create a GitHub repo and push `laptop-controller` (I need your GitHub credentials or you can run the commands I provide),
- Configure Railway / Render deploy steps (I can prepare the exact provider steps),
- Or set up ngrok and share the public URL (I need your ngrok auth token pasted here),
- Or create the double‑click shortcut and a short one‑page instruction for the doctor.

Which action should I take next? (push to GitHub, configure cloud deploy instructions for a specific host, set up ngrok, or create desktop shortcut + quick user guide)
