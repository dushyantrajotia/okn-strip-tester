Render deployment steps (exact)

1) Sign in to https://dashboard.render.com (create free account if needed).

2) Click "New" → "Web Service".

3) Connect your GitHub and select the `laptop-controller` repository and branch `main`.

4) On the "Create a new Web Service" screen set:
   - Name: `okn-controller-ws` (or your chosen name)
   - Environment: `Node` (or `Node 18`)
   - Branch: `main`
   - Build Command: `npm ci`
   - Start Command: `npm start`
   - Health Check Path: `/health`
   - Instance Type / Plan: `Free` (should be available for public repos / small apps)

5) Deploy. After the first deploy finishes, Render will provide a service URL such as `https://okn-controller-ws.onrender.com`.

6) Verify:
   - Open `https://<service>.onrender.com/health` and you should see `OK`.
   - Check logs in Render dashboard to confirm WebSocket server started.

7) Update clients:
   - Frontend (Vercel): set default `serverHost` to `wss://<service>.onrender.com/ws` in `public/index.html` (or leave editable) and redeploy the Vercel site.
   - Flutter app: update `android-app/lib/main.dart` `_socketUrl` to `wss://<service>.onrender.com/ws`, rebuild and distribute the APK.

8) (Optional) Add a custom domain via Render's dashboard and follow instructions to add DNS records at your domain registrar. Once custom domain propagates, update clients to use `wss://controller.example.com/ws`.

Troubleshooting
- If WebSocket fails to connect from browser, check browser console for `ERR_NAME_NOT_RESOLVED` (DNS) or `ERR_SSL_PROTOCOL_ERROR` (SSL issues). Render provides automatic SSL for `*.onrender.com`.
- If connections are established but closed immediately, check server logs for errors and ensure `path: '/ws'` is configured; the server uses `/ws` by default.

Automation
- The repo already contains `render.yaml` so you can import the repo using Render's "Import via render.yaml" to create the service automatically.
