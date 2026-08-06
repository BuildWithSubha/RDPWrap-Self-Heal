document.addEventListener('DOMContentLoaded', () => {
  const API_STATUS = '/api/status';
  const API_REPAIR = '/api/repair';
  const API_DISCONNECT = '/api/disconnect';
  const API_LOGS = '/api/logs';

  const overallBadge = document.getElementById('overall-badge');
  const overallText = document.getElementById('overall-text');
  const btnRepair = document.getElementById('btn-repair');
  const btnRefreshLogs = document.getElementById('btn-refresh-logs');
  
  const valTermsrv = document.getElementById('val-termsrv');
  const badgeIni = document.getElementById('badge-ini');
  const valLoaded = document.getElementById('val-loaded');
  const valListener = document.getElementById('val-listener');
  const valProduct = document.getElementById('val-product');
  const valMaxsessions = document.getElementById('val-maxsessions');
  const valBoottask = document.getElementById('val-boottask');
  const valDailytask = document.getElementById('val-dailytask');
  const sessionCount = document.getElementById('session-count');
  const sessionTableBody = document.getElementById('session-table-body');
  const logOutput = document.getElementById('log-output');
  const lastUpdated = document.getElementById('last-updated');

  async function fetchStatus() {
    try {
      const res = await fetch(API_STATUS);
      if (!res.ok) throw new Error('Status HTTP ' + res.status);
      const data = await res.json();
      renderStatus(data);
    } catch (err) {
      renderError(err.message);
    }
  }

  function renderStatus(data) {
    // Overall Health Badge
    overallBadge.className = 'status-badge ' + (data.overallStatus === 'Healthy' ? 'healthy' : 'warning');
    overallText.textContent = data.overallStatus === 'Healthy' ? 'System Healthy' : 'Repair Recommended';

    // termsrv version
    valTermsrv.textContent = data.termsrvVersion || 'unknown';
    badgeIni.className = 'tag ' + (data.iniHasBuild ? 'success' : 'warning');
    badgeIni.textContent = data.iniHasBuild ? 'ini matching: OK' : 'ini section missing';

    // Loaded & Listener
    valLoaded.className = 'badge-sm ' + (data.wrapperLoaded ? 'yes' : 'no');
    valLoaded.textContent = data.wrapperLoaded ? 'Loaded' : 'Not Loaded';

    valListener.className = 'badge-sm ' + (data.listener3389 ? 'yes' : 'no');
    valListener.textContent = data.listener3389 ? 'Active' : 'Inactive';

    // Product & MaxSessions
    valProduct.textContent = data.productType === 'WinNT' ? 'Client (Win10/11)' : (data.productType === 'ServerNT' ? 'Windows Server' : data.productType);
    valMaxsessions.className = 'badge-sm ' + (data.maxSessions === '0' ? 'yes' : 'no');
    valMaxsessions.textContent = data.maxSessions === '0' ? 'Unlimited (0)' : (data.maxSessions || 'n/a');

    // Tasks
    valBoottask.className = 'badge-sm ' + (data.bootTask ? 'yes' : 'no');
    valBoottask.textContent = data.bootTask ? 'Enabled' : 'Disabled';

    valDailytask.className = 'badge-sm ' + (data.dailyTask ? 'yes' : 'no');
    valDailytask.textContent = data.dailyTask ? 'Enabled' : 'Disabled';

    // Sessions Table
    renderSessions(data.sessions || []);

    // Timestamp
    lastUpdated.textContent = 'Last Updated: ' + (data.timestamp || new Date().toLocaleTimeString());
  }

  function renderSessions(sessions) {
    sessionCount.textContent = `${sessions.length} Active Session${sessions.length === 1 ? '' : 's'}`;
    if (sessions.length === 0) {
      sessionTableBody.innerHTML = `<tr><td colspan="5" class="empty-state">No active Remote Desktop sessions connected.</td></tr>`;
      return;
    }

    sessionTableBody.innerHTML = sessions.map(s => `
      <tr>
        <td><strong>#${escapeHtml(s.id)}</strong></td>
        <td>${escapeHtml(s.user)}</td>
        <td>${escapeHtml(s.name)}</td>
        <td><span class="tag ${s.state === 'Active' ? 'success' : 'neutral'}">${escapeHtml(s.state)}</span></td>
        <td>
          <button class="btn-danger-sm btn-disconnect" data-id="${escapeHtml(s.id)}">Disconnect</button>
        </td>
      </tr>
    `).join('');

    document.querySelectorAll('.btn-disconnect').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const id = e.target.getAttribute('data-id');
        if (confirm(`Disconnect/Logoff session #${id}?`)) {
          disconnectSession(id);
        }
      });
    });
  }

  async function disconnectSession(id) {
    try {
      const res = await fetch(`${API_DISCONNECT}?id=${encodeURIComponent(id)}`, { method: 'POST' });
      const data = await res.json();
      alert(data.message || 'Session disconnected.');
      fetchStatus();
    } catch (err) {
      alert('Failed to disconnect session: ' + err.message);
    }
  }

  async function fetchLogs() {
    try {
      const res = await fetch(API_LOGS);
      if (!res.ok) return;
      const data = await res.json();
      logOutput.textContent = data.logs || 'No log entries available.';
      logOutput.scrollTop = logOutput.scrollHeight;
    } catch (err) {
      logOutput.textContent = 'Failed to fetch logs: ' + err.message;
    }
  }

  async function triggerRepair() {
    btnRepair.disabled = true;
    btnRepair.innerHTML = '⚡ Repairing...';
    try {
      const res = await fetch(API_REPAIR, { method: 'POST' });
      const data = await res.json();
      alert('Self-Heal Repair Completed!\n\n' + (data.output ? data.output.substring(0, 300) + '...' : 'OK'));
    } catch (err) {
      alert('Repair request failed: ' + err.message);
    } finally {
      btnRepair.disabled = false;
      btnRepair.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
        Run Self-Heal Repair
      `;
      fetchStatus();
      fetchLogs();
    }
  }

  function renderError(msg) {
    overallBadge.className = 'status-badge warning';
    overallText.textContent = 'Server Offline';
  }

  function escapeHtml(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  // Event Listeners
  btnRepair.addEventListener('click', triggerRepair);
  btnRefreshLogs.addEventListener('click', fetchLogs);

  // Initial Fetch & Auto Polling
  fetchStatus();
  fetchLogs();
  setInterval(fetchStatus, 5000);
});
