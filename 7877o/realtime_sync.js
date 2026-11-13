/* Shared admin/app realtime refresh behavior. Load after app.js so the
   existing admin subscription uses this handler without opening duplicate
   listeners. RLS continues to govern every query and realtime event. */
(() => {
  const status = document.querySelector('#syncStatus');
  let refreshTimer;

  function showStatus(text, healthy) {
    if (!status) return;
    status.textContent = text;
    status.style.display = 'block';
    status.style.color = healthy ? '#27633a' : '#855c13';
    status.style.background = healthy ? '#edf7ee' : '#fff5df';
  }

  // app.js subscribes to all public-table changes once an admin is verified.
  // Wrap that subscription to surface connection state without adding another
  // realtime channel or exposing any privileged credentials.
  if (typeof sb !== 'undefined') {
    const createChannel = sb.channel.bind(sb);
    sb.channel = (...args) => {
      const channel = createChannel(...args);
      const subscribe = channel.subscribe.bind(channel);
      channel.subscribe = (callback) => subscribe((state, err) => {
        if (!me) return;
        if (state === 'SUBSCRIBED') showStatus('Live sync connected. Changes may take a moment to appear.', true);
        if (state === 'CHANNEL_ERROR' || state === 'TIMED_OUT') {
          showStatus('Live sync is reconnecting. Refresh to check the latest data.', false);
          if (err) console.error('Realtime subscription:', err);
        }
        if (state === 'CLOSED') showStatus('Live sync disconnected. Reload the page to reconnect.', false);
        if (callback) callback(state, err);
      });
      return channel;
    };
  }

  // Refresh only the affected screen, with a small debounce for bursts such as
  // a product update that also changes the stock displayed in the dashboard.
  // Profiles are included so newly registered app customers appear promptly.
  window.onChange = (change) => {
    const table = change?.table;
    if (!table || !me) return;
    if (table === 'orders' && typeof countPending === 'function') countPending();

    if (table === 'messages' && page === 'messages' && typeof refreshChat === 'function') {
      refreshChat();
      return;
    }

    const affected = {
      products: ['products', 'dashboard', 'activity'],
      projects: ['projects', 'dashboard', 'activity'],
      orders: ['orders', 'dashboard', 'activity'],
      feedback: ['feedback', 'activity'],
      profiles: ['customers'],
      messages: ['messages'],
    }[table] || [];

    if (!affected.includes(page) || typeof go !== 'function') return;
    const target = page;
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => { if (me && page === target) go(target, true); }, 500);
  };
})();
