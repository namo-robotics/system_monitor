/* Exercises the actual dashboard script using deterministic host measurements. Requires jsdom. */
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { JSDOM } = require('jsdom');

/* Supply edge cases that are not reliably available on a development machine. */
const fixtures = {
  disk: [
    { mount: '/data', filesystem: '/dev/test1', total_bytes: 4096, used_bytes: 3686, available_bytes: 0, used_percent: 90 },
    { mount: '<img src=x onerror=alert(1)>', filesystem: '/dev/test2', total_bytes: 1024, used_bytes: 256, available_bytes: 700, used_percent: 25 },
  ],
  service: [
    { unit: 'camera.service', load: 'loaded', active: 'failed', sub: 'failed', description: 'Camera <script>alert(1)</script>' },
    { unit: 'robot.service', load: 'loaded', active: 'active', sub: 'running', description: 'Robot' },
    { unit: 'idle.service', load: 'loaded', active: 'inactive', sub: 'dead', description: 'Idle' },
  ],
  network: [{ interface: 'eth0', state: 'up', rx_bytes_per_sec: 1024, tx_bytes_per_sec: 512, rx_bytes: 2048, tx_bytes: 1024, errors: 0, drops: 0 }],
  temperature: [
    { sensor: 'cold', celsius: -5.5, critical_celsius: null, status: 'no threshold' },
    { sensor: 'hot', celsius: 99, critical_celsius: 90, status: 'critical' },
    { sensor: 'unreadable', celsius: null, critical_celsius: 90, status: 'unavailable' },
  ],
};

/* Run table, chart, navigation and missing-data checks without a graphical browser. */
async function main() {
  let sequence = 0;
  let sampleInterval = 1000;
  let unavailable = false;
  const errors = [];
  const dom = new JSDOM(readFileSync(join(__dirname, '..', 'assets', 'dashboard.html'), 'utf8'), {
    url: 'http://localhost/', runScripts: 'dangerously', pretendToBeVisual: true,
    beforeParse(window) {
      const timeout = window.setTimeout.bind(window);
      window.setTimeout = (callback, delay, ...args) => callback.name === 'poll' ? 0 : timeout(callback, delay, ...args);
      window.HTMLCanvasElement.prototype.getContext = () => new Proxy({}, { get: () => () => {} });
      window.addEventListener('error', event => errors.push(event.message));
      window.fetch = async url => ({ ok: true, json: async () => {
        if (url.endsWith('/resources')) {
          sequence++;
          return { timestamp_ms: 1700000000000 + sequence * sampleInterval, interval_ms: sampleInterval, monitors: Object.fromEntries(
            Object.entries(fixtures).map(([key, rows]) => [key, {
              rows: structuredClone(unavailable && key === 'temperature' ? [] : rows), samples: sequence,
              message: unavailable && key === 'temperature' ? 'No hardware sensors available.' : '',
            }])) };
        }
        return { snapshot: { elapsed_ms: 1000, inaccessible: 0, processes: [
          { pid: 12, id: '12:1', exe: '/robot', label: 'Robot', cpu: 10, memory: 2, rss: 1048576 },
        ] }, history: [], status: { top: 10, history_ms: 1000, graph_window_ms: 60000 } };
      } });
    },
  });
  try {
    const { window } = dom;
    const $ = id => window.document.getElementById(id);
    /* Apply the same URL navigation used by the horizontal tabs. */
    const select = key => { window.location.hash = key; window.selectMonitor(); };
    await new Promise(resolve => setImmediate(resolve));
    await window.poll();
    assert.equal($('tab-process').getAttribute('aria-selected'), 'true');
    assert.equal($('rows').children.length, 1);
    assert.equal(window.document.querySelectorAll('[role=tab]').length, 5);
    assert.ok($('history'));
    for (const key of Object.keys(fixtures)) {
      select(key);
      assert.equal($(key + '-view').hidden, false);
      assert.equal($(key + '-rows').children.length, fixtures[key].length);
      assert.ok($(key + '-head').querySelector('th[scope=col]'));
      assert.ok($(key + '-chart').children.length);
      for (const other of ['process', ...Object.keys(fixtures)]) assert.equal($(other + '-view').hidden, other !== key);
    }
    select('disk');
    assert.equal($('disk-chart').querySelectorAll('.meter-fill').length, 2);
    assert.equal($('disk-chart').querySelector('.meter-fill').style.width, '90%');
    assert.ok($('disk-rows').textContent.includes('0 B'));
    assert.ok($('disk-rows').textContent.includes('<img src=x'));
    assert.equal($('disk-rows').querySelectorAll('img, script').length, 0);
    $('disk-filter').value = '/data'; $('disk-filter').dispatchEvent(new window.Event('input'));
    assert.equal($('disk-rows').children.length, 1);
    assert.equal($('disk-chart').querySelectorAll('.bar-row').length, 1);
    select('service');
    assert.equal($('service-chart').querySelectorAll('.stacked-segment').length, 3);
    assert.ok($('service-rows').querySelector('.status.bad'));
    assert.equal($('service-rows').querySelectorAll('script').length, 0);
    $('service-filter').value = 'camera'; $('service-filter').dispatchEvent(new window.Event('input'));
    assert.equal($('service-chart').querySelector('.stacked-segment').style.width, '100%');
    select('temperature');
    assert.ok($('temperature-rows').lastElementChild.textContent.includes('unreadable'));
    assert.equal($('temperature-chart').querySelectorAll('.meter-fill').length, 2);
    assert.equal($('temperature-chart').querySelectorAll('.threshold').length, 1);
    $('temperature-head').querySelector('[data-field=celsius] button').click();
    assert.ok($('temperature-rows').firstElementChild.textContent.includes('cold'));
    assert.ok($('temperature-rows').lastElementChild.textContent.includes('unreadable'));
    assert.equal($('temperature-head').querySelector('[data-field=celsius]').getAttribute('aria-sort'), 'ascending');
    select('network');
    assert.ok($('network-chart').querySelector('svg[role=img]'));
    assert.equal($('network-chart').querySelectorAll('path').length, 2);
    assert.ok(!$('network-chart').innerHTML.includes('NaN'));
    $('network-interface').value = 'eth0'; $('network-interface').dispatchEvent(new window.Event('change'));
    assert.ok($('network-chart').querySelector('svg').getAttribute('aria-label').includes('eth0'));
    const frozen = $('network-updated').textContent;
    $('pause').click(); await window.poll();
    assert.equal($('network-updated').textContent, frozen);
    $('pause').click();
    assert.notEqual($('network-updated').textContent, frozen);
    fixtures.network[0].rx_bytes_per_sec = null; await window.poll();
    assert.ok($('network-rows').textContent.includes('N/A'));
    fixtures.network[0].rx_bytes_per_sec = 2048; await window.poll();
    assert.ok(($('network-chart').querySelector('path').getAttribute('d').match(/M/g) || []).length >= 2);
    for (let i = 0; i < 125; i++) await window.poll();
    assert.ok(window.eval('networkHistory.length') <= 61, 'network history must be bounded');
    sampleInterval = 5000; await window.poll(); await window.poll();
    assert.ok($('network-chart').querySelector('path').getAttribute('d').includes('L'), 'configured slow samples should connect');
    select('temperature'); unavailable = true; await window.poll();
    assert.equal($('temperature-notice').hidden, false);
    assert.ok($('temperature-chart').textContent.includes('No sensor measurements'));
    assert.equal($('temperature-chart').querySelectorAll('.meter-fill').length, 0);
    assert.deepEqual(errors, []);
    console.log('PASS dashboard: five tables/charts, sorting, filtering, safe text, missing values, pause, network gaps and bounded history');
  } finally { dom.window.close(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
