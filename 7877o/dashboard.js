/* Read-only dashboard. Every query uses the already-verified admin client;
   database RLS remains the authorization boundary. No customer data is fetched. */
(function (root) {
  'use strict';
  const statuses = ['pending', 'confirmed', 'processing', 'delivered', 'cancelled'];
  const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const number = value => Number(value).toLocaleString();

  function daysEndingToday(now) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    return Array.from({ length: 7 }, (_, i) => {
      const start = new Date(today); start.setDate(today.getDate() - 6 + i);
      const end = new Date(start); end.setDate(start.getDate() + 1);
      return { start: start.toISOString(), end: end.toISOString(), label: start.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' }) };
    });
  }

  async function count(client, table, filter) {
    let query = client.from(table).select('id', { count: 'exact', head: true });
    if (filter) query = filter(query);
    const result = await query;
    if (result.error || !Number.isSafeInteger(result.count) || result.count < 0) throw new Error('Count unavailable');
    return result.count;
  }

  function metric(label, result, detail, tone) {
    const value = result.status === 'fulfilled' ? number(result.value) : 'Unavailable';
    return `<article class="dash-metric dash-${tone}"><p>${label}</p><strong>${value}</strong><span>${detail}</span></article>`;
  }

  function chart(rows) {
    const max = Math.max(...rows.map(row => row.value), 1);
    return `<ul class="chart-list">${rows.map(row => `<li><span class="chart-label">${escapeHtml(row.label)}</span><span class="chart-track" aria-hidden="true"><span class="chart-fill" style="width:${(row.value / max * 100).toFixed(2)}%"></span></span><strong>${number(row.value)}</strong></li>`).join('')}</ul>`;
  }

  async function mount({ container, client, isActive = () => true, now = () => new Date() }) {
    container.innerHTML = '<p class="dashboard-loading" role="status">Loading your dashboard…</p>';
    const days = daysEndingToday(now());
    const metrics = [
      count(client, 'orders'),
      null, // The pending status count below is shared with this metric.
      count(client, 'products'),
      count(client, 'projects')
    ];
    const statusCounts = statuses.map(status => count(client, 'orders', q => q.eq('status', status)));
    statusCounts.push(count(client, 'orders', q => q.or('status.is.null,status.not.in.(' + statuses.join(',') + ')')));
    const dayCounts = days.map(day => count(client, 'orders', q => q.gte('created_at', day.start).lt('created_at', day.end)));
    const results = await Promise.allSettled([...metrics, ...statusCounts, ...dayCounts]);
    if (!isActive() || !container.isConnected) return;
    const m = results.slice(0, 4), s = results.slice(4, 10), d = results.slice(10);
    m[1] = s[0];
    const failed = results.some(result => result.status === 'rejected');
    const statusRows = [...statuses.map(x => x[0].toUpperCase() + x.slice(1)), 'Other'].map((label, i) => ({ label, value: s[i].value }));
    const dayRows = days.map((day, i) => ({ label: day.label, value: d[i].value }));
    const statusBody = s.some(x => x.status === 'rejected') ? '<p class="chart-message">Order statuses could not be loaded. Try refreshing.</p>' :
      s.every(x => x.value === 0) ? '<p class="chart-message">No orders yet. Status counts will appear here.</p>' : chart(statusRows);
    const dayBody = d.some(x => x.status === 'rejected') ? '<p class="chart-message">Recent orders could not be loaded. Try refreshing.</p>' :
      d.every(x => x.value === 0) ? '<p class="chart-message">No orders were placed in the last 7 days.</p>' : chart(dayRows);
    container.innerHTML = `<div class="dashboard">
      <section class="dash-hero" aria-labelledby="overview-heading"><div><p class="eyebrow">GRAPHEN BAGS · ADMIN</p><h3 id="overview-heading">Your business at a glance</h3><p>Keep track of orders and your collection in one place.</p></div><div class="hero-mark" aria-hidden="true"><span>G</span><small>BAGS</small></div></section>
      ${failed ? '<div class="dash-alert" role="alert">Some dashboard data is unavailable. Check your connection and refresh. <button type="button" class="btn ghost" data-dash-retry>Try again</button></div>' : ''}
      <section aria-label="Business overview" class="dash-metrics">
        ${metric('All orders', m[0], 'All time', 'dark')}
        ${metric('Pending orders', m[1], 'Need your attention', 'warm')}
        ${metric('Products', m[2], 'Records you can access', 'light')}
        ${metric('Projects', m[3], 'Records you can access', 'light')}
      </section>
      <div class="dash-charts">
        <section class="dash-panel" aria-labelledby="trend-heading"><div class="panel-heading"><div><p class="eyebrow">ORDER ACTIVITY</p><h3 id="trend-heading">Orders over time</h3></div><span class="panel-pill">Last 7 days</span></div><p class="panel-note">Orders placed per day, including today. Dates use your device's time zone.</p>${dayBody}</section>
        <section class="dash-panel" aria-labelledby="status-heading"><div class="panel-heading"><div><p class="eyebrow">ORDER PIPELINE</p><h3 id="status-heading">Orders by status</h3></div><span class="panel-pill">All time</span></div><p class="panel-note">Current status of each order, not payment or revenue.</p>${statusBody}</section>
      </div>
      <p class="dash-footnote">Counts include only records accessible to this account under database permissions and may change while loading. Delivery fees are quoted separately; no revenue total is shown here.</p>
    </div>`;
    const retry = container.querySelector('[data-dash-retry]');
    if (retry) retry.addEventListener('click', () => mount({ container, client, isActive, now }));
  }

  const api = { mount, daysEndingToday, count, chart };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.GraphensDashboard = api;
})(typeof window !== 'undefined' ? window : null);
