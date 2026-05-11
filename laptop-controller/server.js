const express = require('express');
const http = require('http');
const path = require('path');
const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;

const app = express();
app.use(express.static(path.join(__dirname, 'public')));

// Add a health check endpoint
app.get('/health', (req, res) => {
  res.send('OK');
});

// Add a dedicated WS endpoint for explicit WebSocket upgrades
app.get('/ws', (req, res) => {
  console.log('[HTTP] GET /ws request received');
  res.send('WebSocket endpoint. Use WebSocket protocol.');
});

const server = http.createServer(app);

// Create WebSocket server with explicit path handling
const wss = new WebSocket.Server({ 
  server,
  path: '/ws'
});

console.log('[INIT] WebSocket server created on path /ws');

let phoneSocket = null;
const controllerSockets = new Set();

function safeSend(ws, payload) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return;
  }
  ws.send(JSON.stringify(payload));
}

function broadcastControllers(payload) {
  for (const ws of controllerSockets) {
    safeSend(ws, payload);
  }
}

function publishPhoneStatus() {
  broadcastControllers({
    type: 'phone-status',
    connected: !!phoneSocket && phoneSocket.readyState === WebSocket.OPEN,
  });
}

wss.on('connection', (ws) => {
  let role = 'unknown';
  console.log(`[WS] New connection attempt - Total sockets: ${wss.clients.size}`);

  safeSend(ws, {
    type: 'hello',
    message: 'Identify yourself using {"type":"identify","role":"controller|phone"}',
  });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch (err) {
      console.log('[WS] Invalid JSON received:', raw.toString());
      safeSend(ws, { type: 'error', message: 'Invalid JSON' });
      return;
    }

    console.log(`[WS] Message from ${role}:`, msg.type);

    if (msg.type === 'identify') {
      if (msg.role === 'phone') {
        role = 'phone';
        console.log('[WS] Phone identified');
        if (phoneSocket && phoneSocket !== ws && phoneSocket.readyState === WebSocket.OPEN) {
          safeSend(phoneSocket, { type: 'server', message: 'Another phone connected, this session was replaced.' });
          phoneSocket.close();
        }
        phoneSocket = ws;
        safeSend(ws, { type: 'identified', role: 'phone' });
        publishPhoneStatus();
        return;
      }

      if (msg.role === 'controller') {
        role = 'controller';
        controllerSockets.add(ws);
        console.log('[WS] Controller identified - Total controllers:', controllerSockets.size);
        safeSend(ws, { type: 'identified', role: 'controller' });
        publishPhoneStatus();
        return;
      }

      safeSend(ws, { type: 'error', message: 'Unknown role' });
      return;
    }

    if (role === 'controller' && msg.type === 'command') {
      if (!phoneSocket || phoneSocket.readyState !== WebSocket.OPEN) {
        safeSend(ws, { type: 'error', message: 'Phone is not connected' });
        publishPhoneStatus();
        return;
      }
      safeSend(phoneSocket, msg.payload);
      return;
    }

    if (role === 'phone') {
      broadcastControllers({
        type: 'phone-message',
        payload: msg,
      });
      return;
    }

    safeSend(ws, { type: 'error', message: 'Identify first' });
  });

  ws.on('close', () => {
    console.log(`[WS] Connection closed for ${role}`);
    if (ws === phoneSocket) {
      phoneSocket = null;
    }
    controllerSockets.delete(ws);
    publishPhoneStatus();
  });

  ws.on('error', (err) => {
    console.log(`[WS] Error for ${role}:`, err.message);
    if (ws === phoneSocket) {
      phoneSocket = null;
    }
    controllerSockets.delete(ws);
    publishPhoneStatus();
  });
});

wss.on('error', (err) => {
  console.log('[WSS] Error:', err.message);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[SERVER] OKN controller running on http://0.0.0.0:${PORT}`);
  console.log(`[SERVER] WebSocket endpoint: wss://<railway-domain>/ws`);
  console.log(`[SERVER] Health check: https://<railway-domain>/health`);
});
