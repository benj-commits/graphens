/* Delivery fee screen. The host must supply an authenticated Supabase client
   and a container after its own admin navigation/authentication succeeds:
   GraphensDeliveryFeeAdmin.mount({ container: view, client: supabaseClient });
   Authorization and fee/state transitions must be enforced by the database. */
(() => {
  'use strict';
  const columns = 'id,customer_name,address,total,delivery_latitude,delivery_longitude,delivery_fee,delivery_fee_status,delivery_fee_revision,created_at';
  const responses = {
    awaiting_quote: 'Awaiting quote', offered: 'Offered — waiting for customer',
    accepted: 'Accepted by customer', declined: 'Declined by customer'
  };

  function mount({ container, client }) {
    if (!container || typeof container.replaceChildren !== 'function' || !client ||
        typeof client.from !== 'function' || typeof client.rpc !== 'function') {
      throw new TypeError('An existing container and authenticated Supabase client are required.');
    }
    const el = (tag, text, className) => {
      const node = document.createElement(tag);
      if (text !== undefined) node.textContent = String(text);
      if (className) node.className = className;
      return node;
    };
    const money = value => {
      if (value === null || value === undefined || value === '' || !Number.isFinite(Number(value))) return 'Not available';
      return 'UGX ' + Number(value).toLocaleString('en-UG');
    };
    const coordinate = (value, limit) => {
      if (value === null || value === undefined || String(value).trim() === '') return null;
      const n = Number(value);
      return Number.isFinite(n) && Math.abs(n) <= limit ? n : null;
    };
    const errorText = error => error && error.message ? error.message : String(error || 'Unknown error');
    const shell = el('section');
    const heading = el('h2', 'Delivery fees');
    const refresh = el('button', 'Refresh', 'btn');
    refresh.type = 'button';
    const message = el('p');
    message.setAttribute('role', 'status');
    message.setAttribute('aria-live', 'polite');
    const list = el('div', undefined, 'list');
    shell.append(heading, refresh, message, list);
    container.replaceChildren(shell);
    let loading = false;
    const pending = new Set();

    function line(card, label, value) {
      const p = el('p');
      p.append(el('strong', label + ': '), document.createTextNode(value == null || value === '' ? 'Not available' : String(value)));
      card.append(p);
    }
    function renderOrder(order) {
      const card = el('article', undefined, 'card');
      card.append(el('h3', 'Order ' + String(order.id)));
      line(card, 'Customer', order.customer_name);
      line(card, 'Delivery address', order.address);
      const lat = coordinate(order.delivery_latitude, 90);
      const lng = coordinate(order.delivery_longitude, 180);
      if (lat !== null && lng !== null) {
        const link = el('a', 'Open customer location in map');
        link.href = 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(lat + ',' + lng);
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        card.append(link);
      }
      // Existing secure_order trigger sets total to the server-calculated item subtotal.
      line(card, 'Item subtotal (recorded order total)', money(order.total));
      line(card, 'Delivery fee', money(order.delivery_fee));
      line(card, 'Customer response', responses[order.delivery_fee_status] || (order.delivery_fee_status ? 'Unknown status: ' + order.delivery_fee_status : 'Not available'));
      line(card, 'Fee revision', order.delivery_fee_revision);
      const form = el('form');
      const label = el('label', 'Delivery fee (whole UGX) ');
      const input = el('input');
      input.type = 'text';
      input.inputMode = 'numeric';
      input.required = true;
      input.autocomplete = 'off';
      if (order.delivery_fee != null && Number.isSafeInteger(Number(order.delivery_fee)) && Number(order.delivery_fee) >= 0) input.value = String(order.delivery_fee);
      label.append(input);
      const button = el('button', 'Offer delivery fee', 'btn');
      button.type = 'submit';
      const feedback = el('p');
      feedback.setAttribute('role', 'status');
      feedback.setAttribute('aria-live', 'polite');
      form.append(label, button, feedback);
      form.addEventListener('submit', async event => {
        event.preventDefault();
        if (pending.size || loading) {
          feedback.textContent = 'Please wait for the current request to finish.';
          return;
        }
        const raw = input.value.trim();
        const fee = Number(raw);
        if (!/^\d+$/.test(raw) || !Number.isSafeInteger(fee) || fee < 0) {
          feedback.textContent = 'Enter a non-negative whole number of UGX.';
          return;
        }
        pending.add(order.id);
        button.disabled = true;
        input.disabled = true;
        refresh.disabled = true;
        feedback.textContent = 'Sending offer…';
        try {
          const result = await client.rpc('set_delivery_fee_v1', { p_order_id: order.id, p_fee: fee });
          if (result.error) throw result.error;
          pending.delete(order.id);
          await load('Fee submitted. The customer response is shown below.');
        } catch (error) {
          feedback.textContent = 'Could not send fee: ' + errorText(error);
        } finally {
          pending.delete(order.id);
          button.disabled = false;
          input.disabled = false;
          refresh.disabled = loading || pending.size > 0;
        }
      });
      card.append(form);
      return card;
    }
    async function load(successMessage) {
      if (loading || pending.size) return;
      loading = true;
      refresh.disabled = true;
      message.textContent = 'Loading orders…';
      try {
        const result = await client.from('orders').select(columns).order('created_at', { ascending: false });
        if (result.error) throw result.error;
        const orders = result.data || [];
        list.replaceChildren(...orders.map(renderOrder));
        message.textContent = successMessage || (orders.length ? '' : 'No orders found.');
      } catch (error) {
        list.replaceChildren();
        message.textContent = 'Could not load orders: ' + errorText(error);
      } finally {
        loading = false;
        refresh.disabled = pending.size > 0;
      }
    }
    refresh.addEventListener('click', () => load());
    load();
    return { refresh: () => load() };
  }
  window.GraphensDeliveryFeeAdmin = Object.freeze({ mount });
})();
