const WIDTH_OPTIONS = [28.8, 23.3, 17, 11.5, 5.8, 2.87, 1.43];
const SPEED_OPTIONS = [20, 30, 40, 50, 60, 70, 80, 90, 100, 160];

const CONTRAST_OPTIONS = [
  { value: 'full', label: 'Full Contrast' },
  { value: '1', label: 'Level 1 - 50%' },
  { value: '2', label: 'Level 2 - 75%' },
  { value: '3', label: 'Level 3 - 87.5%' },
  { value: '4', label: 'Level 4 - 93.75%' },
  { value: '5', label: 'Level 5 - 96.8%' },
  { value: '6', label: 'Level 6 - 98.44%' },
];

const state = {
  sync: false,
  ws: null,
  vrModeEnabled: true,
  left: {
    widthMm: 11.5,
    speedDegPerSec: 60,
    contrastLevel: 'full',
    stripColor: '#ff0000',
    bgColor: '#000000',
    direction: 'rtl',
  },
  right: {
    widthMm: 11.5,
    speedDegPerSec: 60,
    contrastLevel: 'full',
    stripColor: '#ff0000',
    bgColor: '#000000',
    direction: 'rtl',
  },
};

const el = {
  host: document.getElementById('serverHost'),
  reconnectBtn: document.getElementById('reconnectBtn'),
  status: document.getElementById('phoneStatus'),
  syncMode: document.getElementById('syncMode'),
  startBoth: document.getElementById('startBothBtn'),
  stopBoth: document.getElementById('stopBothBtn'),
  vrToggle: document.getElementById('vrToggleBtn'),
  logPanel: document.getElementById('logPanel'),
};

function log(msg) {
  const t = new Date().toLocaleTimeString();
  el.logPanel.textContent = `[${t}] ${msg}\n${el.logPanel.textContent}`.slice(0, 8000);
}

function showEyeAlert(msg) {
  const alertEl = document.getElementById('eyeAlert');
  if (alertEl) {
    alertEl.textContent = msg;
    alertEl.style.display = 'block';
    setTimeout(() => {
      alertEl.style.display = 'none';
    }, 3000);
  }
}

function setPhoneStatus(connected) {
  el.status.textContent = connected ? 'Phone: Connected' : 'Phone: Disconnected';
  el.status.classList.toggle('connected', connected);
  el.status.classList.toggle('disconnected', !connected);
}

function wsUrlFromHost(host) {
  const pageWsProtocol = location.protocol === 'https:' ? 'wss' : 'ws';
  const trimmed = host.trim();
  let baseUrl;
  
  if (!trimmed) {
    baseUrl = `${pageWsProtocol}://${location.host}`;
  } else if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
    baseUrl = trimmed;
  } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    const u = new URL(trimmed);
    const protocol = u.protocol === 'https:' ? 'wss' : 'ws';
    baseUrl = `${protocol}://${u.host}`;
  } else {
    baseUrl = `${pageWsProtocol}://${trimmed}`;
  }
  
  // Ensure /ws path is appended
  if (!baseUrl.endsWith('/ws')) {
    baseUrl += '/ws';
  }
  return baseUrl;
}

function sendCommand(payload) {
  if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
    log('Controller socket is not connected to the server.');
    return;
  }
  state.ws.send(JSON.stringify({ type: 'command', payload }));
}

function buildUpdatePayload(eye, data) {
  return {
    action: 'update',
    eye,
    params: {
      widthMm: data.widthMm,
      speedDegPerSec: Number(data.speedDegPerSec),
      contrastLevel: data.contrastLevel === 'full' ? 'full' : Number(data.contrastLevel),
      stripColor: data.stripColor.toUpperCase(),
      bgColor: data.bgColor.toUpperCase(),
      direction: data.direction,
    },
  };
}

function applySync(sourceEye) {
  if (!state.sync) {
    return;
  }
  const source = sourceEye === 'left' ? state.left : state.right;
  const targetEye = sourceEye === 'left' ? 'right' : 'left';
  Object.assign(state[targetEye], source);
  hydrateEyeUi(targetEye);
  sendCommand(buildUpdatePayload(targetEye, state[targetEye]));
}

function connectControllerSocket() {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) {
    state.ws.close();
  }

  const wsUrl = wsUrlFromHost(el.host.value);
  log(`Connecting controller socket to ${wsUrl}`);
  const ws = new WebSocket(wsUrl);
  state.ws = ws;

  ws.addEventListener('open', () => {
    ws.send(JSON.stringify({ type: 'identify', role: 'controller' }));
    log('Controller connected to server.');
  });

  ws.addEventListener('message', (event) => {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }

    if (msg.type === 'phone-status') {
      setPhoneStatus(Boolean(msg.connected));
      return;
    }

    if (msg.type === 'phone-message') {
      const payload = msg.payload;
      if (payload.type === 'eye-alert') {
        const alertMsg = `⚠️  GAZE ALERT: ${payload.movement}`;
        log(alertMsg);
        showEyeAlert(alertMsg);
      } else {
        log(`Phone -> ${JSON.stringify(msg.payload)}`);
      }
      return;
    }

    if (msg.type === 'error') {
      log(`Server error: ${msg.message}`);
      return;
    }

    if (msg.type === 'identified') {
      log(`Controller identified as ${msg.role}`);
    }
  });

  ws.addEventListener('close', () => {
    setPhoneStatus(false);
    log('Controller socket closed.');
  });

  ws.addEventListener('error', () => {
    log('Controller socket error.');
  });
}

function populateSelect(select, options, toLabel, toValue, defaultValue) {
  select.innerHTML = '';
  for (const item of options) {
    const option = document.createElement('option');
    option.value = toValue(item);
    option.textContent = toLabel(item);
    if (String(option.value) === String(defaultValue)) {
      option.selected = true;
    }
    select.appendChild(option);
  }
}

function bindEye(eye) {
  const model = state[eye];
  const prefix = eye;

  const widthEl = document.getElementById(`${prefix}-width`);
  const speedEl = document.getElementById(`${prefix}-speed`);
  const speedValueEl = document.getElementById(`${prefix}-speed-value`);
  const contrastEl = document.getElementById(`${prefix}-contrast`);
  const stripEl = document.getElementById(`${prefix}-strip`);
  const bgEl = document.getElementById(`${prefix}-bg`);
  const directionEl = document.getElementById(`${prefix}-direction`);

  populateSelect(widthEl, WIDTH_OPTIONS, (v) => `${v} mm`, (v) => v, model.widthMm);
  populateSelect(
    contrastEl,
    CONTRAST_OPTIONS,
    (v) => v.label,
    (v) => v.value,
    model.contrastLevel
  );

  populateSelect(
    speedEl,
    SPEED_OPTIONS,
    (v) => `${v}°/s`,
    (v) => v,
    model.speedDegPerSec
  );
  speedValueEl.textContent = `${model.speedDegPerSec}°/s`;
  stripEl.value = model.stripColor;
  bgEl.value = model.bgColor;
  directionEl.value = model.direction;

  widthEl.addEventListener('change', () => {
    model.widthMm = Number(widthEl.value);
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });

  speedEl.addEventListener('change', () => {
    model.speedDegPerSec = Number(speedEl.value);
    speedValueEl.textContent = `${model.speedDegPerSec}°/s`;
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });

  contrastEl.addEventListener('change', () => {
    model.contrastLevel = contrastEl.value;
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });

  stripEl.addEventListener('input', () => {
    model.stripColor = stripEl.value;
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });

  bgEl.addEventListener('input', () => {
    model.bgColor = bgEl.value;
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });

  directionEl.addEventListener('change', () => {
    model.direction = directionEl.value;
    sendCommand(buildUpdatePayload(eye, model));
    applySync(eye);
  });
}

function hydrateEyeUi(eye) {
  const model = state[eye];
  document.getElementById(`${eye}-width`).value = String(model.widthMm);
  document.getElementById(`${eye}-speed`).value = String(model.speedDegPerSec);
  document.getElementById(`${eye}-speed-value`).textContent = `${model.speedDegPerSec}°/s`;
  document.getElementById(`${eye}-contrast`).value = String(model.contrastLevel);
  document.getElementById(`${eye}-strip`).value = model.stripColor;
  document.getElementById(`${eye}-bg`).value = model.bgColor;
  document.getElementById(`${eye}-direction`).value = model.direction;
}

function bootstrap() {
  bindEye('left');
  bindEye('right');

  document.querySelectorAll('.eye-action').forEach((btn) => {
    btn.addEventListener('click', () => {
      const eye = btn.dataset.eye;
      const action = btn.dataset.action;
      sendCommand({ action, eye });
      if (state.sync) {
        const mirrorEye = eye === 'left' ? 'right' : 'left';
        sendCommand({ action, eye: mirrorEye });
      }
    });
  });

  el.startBoth.addEventListener('click', () => {
    sendCommand({ action: 'start', eye: 'both' });
  });

  el.vrToggle.addEventListener('click', () => {
    state.vrModeEnabled = !state.vrModeEnabled;
    el.vrToggle.textContent = state.vrModeEnabled ? 'VR: ON' : 'VR: OFF';
    sendCommand({ action: 'vrmode', enabled: state.vrModeEnabled });
  });

  el.stopBoth.addEventListener('click', () => {
    sendCommand({ action: 'stop', eye: 'both' });
  });

  el.syncMode.addEventListener('change', () => {
    state.sync = el.syncMode.checked;
    if (state.sync) {
      Object.assign(state.right, state.left);
      hydrateEyeUi('right');
      sendCommand(buildUpdatePayload('right', state.right));
      log('Sync mode enabled. Right eye mirrored from left eye.');
    } else {
      log('Sync mode disabled. Eyes can be controlled independently.');
    }
  });

  el.reconnectBtn.addEventListener('click', connectControllerSocket);

  connectControllerSocket();
  setPhoneStatus(false);
}

bootstrap();
