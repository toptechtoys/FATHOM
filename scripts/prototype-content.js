class Component extends DCLogic {
  state = { k: 'cpu', ob: false, tick: 0, rsel: { derived: true, caches: true, fcp: true, snap: false, logs: false } };
  fr = React.createRef();
  sim = { cpu: 22, gpu: 16, net: 1240, up: 84, pwr: 6.8, hot: 41, cores: [34, 28, 18, 12, 42, 38, 9, 6] };
  hist = { cpu: Array(60).fill(22), gpu: Array(60).fill(16), net: Array(60).fill(1200), pwr: Array(60).fill(6.8) };
  componentDidMount() {
    this.iv = setInterval(() => { if (this.props.ticking !== false) this.step(); }, 1000);
    if (!localStorage.getItem('fathom-enh-ob')) this.setState({ ob: true });
    window.addEventListener('keydown', this.keys);
  }
  componentWillUnmount() { clearInterval(this.iv); window.removeEventListener('keydown', this.keys); }
  step() {
    const w = (v, lo, hi, j) => Math.min(hi, Math.max(lo, v + (Math.random() - .5) * j));
    const s = this.sim;
    s.cpu = w(s.cpu, 6, 88, 9); s.gpu = w(s.gpu, 3, 70, 7); s.net = w(s.net, 40, 4800, 620); s.up = w(s.up, 10, 400, 60);
    s.pwr = +(3.4 + s.cpu * .07 + s.gpu * .04).toFixed(1); s.hot = +(38 + s.cpu * .1).toFixed(1);
    s.cores = s.cores.map((c, i) => w(c, 1, 96, i < 4 ? 14 : 18));
    ['cpu', 'gpu', 'net', 'pwr'].forEach(k => { const b = this.hist[k]; b.push(s[k]); if (b.length > 60) b.shift(); });
    this.setState(st => ({ tick: st.tick + 1 }));
  }
  cr = React.createRef();
  order = () => Object.keys(this.TT);
  stepNav = (d) => { const o = this.order(); const i = o.indexOf(this.state.k); this.go(o[(i + d + o.length) % o.length]); };
  keys = (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowRight') { e.preventDefault(); this.stepNav(1); }
    if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') { e.preventDefault(); this.stepNav(-1); }
  };
  go = (k) => {
    if (k === this.state.k) return;
    this.setState({ k });
    const c = this.cr.current;
    if (c) {
      c.scrollTop = 0;
      const rm = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (!rm && c.animate) c.animate([{ opacity: 0, transform: 'translateY(12px)' }, { opacity: 1, transform: 'none' }], { duration: 450, easing: 'cubic-bezier(.16,1,.3,1)' });
    }
    const f = this.fr.current; try { if (f && f.contentWindow && f.contentWindow.go) f.contentWindow.go(k); } catch (e) {}
  };
  dismiss = (scan) => {
    try { localStorage.setItem('fathom-enh-ob', '1'); } catch (e) {}
    this.setState({ ob: false }); if (scan) this.go('scan');
  };
  W = { menubar:['#062737','#0C6076','#1FA3B8','#B9EEF5','#0B6273'], home:['#08133A','#1B3E86','#3F79CE','#C6DBFB','#1C3E82'], scan:['#1B0E42','#4E23A0','#8B5CF6','#DDD1FE','#5B21B6'], cpu:['#04203A','#0B5296','#2E8BE0','#BCDDFB','#0C4E8C'], gpu:['#2A0838','#6D1580','#B040C8','#F3C8FC','#6B1A7E'], mem:['#12063A','#3B1D9E','#6F4BE0','#D2C6FE','#3A1F94'], sensors:['#3A1206','#96380A','#DE7A17','#FDDCAE','#9A4109'], network:['#03302C','#0A7A72','#2CB9AC','#B3F5EE','#087269'], bt:['#062B1E','#0D7A4E','#2CBE7C','#B9F8D8','#0A7350'], storage:['#04263A','#0C6B90','#2BB6D4','#B6EEFA','#0B6A85'], timeline:['#26063E','#6B1AA0','#B23FD4','#F0CBFB','#6D1D9C'], explore:['#0C1445','#243397','#5566DC','#C7D0FF','#26339B'], reclaim:['#032A1F','#0A7150','#26B87C','#B4F7D6','#08704F'], endurance:['#051E2C','#0F5A72','#33A2B4','#AFEBEE','#0D6D7C'], attrib:['#101334','#333A80','#6B74CE','#CDD2FF','#3A4299'], digest:['#28211A','#6F5936','#BE9A56','#FAEAC6','#7E6534'], apps:['#141046','#3A2AA8','#7059E8','#D5CDFF','#3B2CA4'], cloud:['#07234A','#12559E','#3691E0','#C0DFFB','#11529A'], maint:['#331A05','#8A4A0B','#D08A1D','#FBE1B4','#8B4C0C'], ssd:['#0A1F2E','#1D5570','#4A93AE','#C3E6F2','#1B5570'] };
  RAD = { scan:'30%', storage:'50% / 34%', timeline:'46% 54% 50% 50% / 50% 46% 54% 50%', explore:'20%', reclaim:'62% 38% 58% 42% / 42% 62% 38% 58%', endurance:'50% 50% 46% 46% / 58% 58% 42% 42%', attrib:'16% 46% 16% 46% / 46% 16% 46% 16%', apps:'18% 42% 18% 42%', cloud:'46% 54% 46% 54% / 54% 46% 54% 46%', maint:'28% 28% 20% 20%', ssd:'36% / 28%' };
  GLY = { apps:1, attrib:1, cloud:1, endurance:1, explore:1, maint:1, reclaim:1, scan:1, ssd:1, storage:1, timeline:1 };
  TT = { menubar:'Menu Bar', digest:'Weekly digest', home:'Home', scan:'Deep Scan', cpu:'CPU', gpu:'GPU', mem:'Memory', sensors:'Sensors & Power', network:'Network', bt:'Bluetooth', storage:'Storage', timeline:'Timeline', explore:'Explore', reclaim:'Reclaim', endurance:'Endurance', attrib:'Attribution', apps:'Applications', cloud:'Cloud', maint:'Maintenance', ssd:'SSD Health' };
  SUB = { menubar:'Live preview', home:'MacBook Air M2 · all systems sampled', scan:'Last full pass 2 h ago', cpu:'Apple M2 · 8 cores · sampling 1 Hz while visible', gpu:'Apple M2 · 10 cores', mem:'16 GB unified · sampling 1 Hz', sensors:'22 sensors · 3 s interval', network:'Wi-Fi en0 · 802.11ax', bt:'3 devices paired', storage:'Macintosh HD · 494.38 GB · APFS', timeline:'142 days recorded', explore:'1,184,203 nodes indexed', reclaim:'Dry run · nothing moved', endurance:'Read only', attrib:'Written today, traced to who wrote it', digest:'Next: Sunday 09:00', apps:'136 applications', cloud:'iCloud Drive', maint:'6 tasks · each states its cost', ssd:'NVMe SMART · read only' };
  E = { home:'Run the first Deep Scan to fill this screen. The live monitors already work.', scan:'No pass has run yet. The first Deep Scan takes about four minutes and reads every volume once.', storage:'The tree has not been indexed. Until the first scan finishes, the only honest numbers are the volume totals.', timeline:'There is no history to draw. The first column appears at midnight, and the chart admits every day it missed.', explore:'Nothing to explore until the first scan. We do not guess at a tree we have not read.', reclaim:'No rules have been evaluated. Reclaim never proposes what a scan has not verified.', endurance:'One SMART reading exists. A projection needs a rate, and a rate needs time.', attrib:'Attribution starts recording now. Yesterday is unknowable and stays that way.', digest:'The first digest arrives Sunday at 09:00. If the week was quiet, it will say so and stop.', apps:'Footprints are computed during the first scan, including what apps left in six other places.', cloud:'iCloud occupancy is read during the first scan. The claim and the truth usually differ.', maint:'Task costs are already known. Their savings are measured after the first scan.' };
  sp(key, max, label) {
    const b = this.hist[key], n = b.length;
    const pts = b.map((v, i) => ((i * (1000 / (n - 1))).toFixed(0)) + ',' + ((54 - Math.min(1, v / max) * 48).toFixed(1))).join(' ');
    return { isSpark: true, label, pts, poly: '0,56 ' + pts + ' 1000,56' };
  }
  tbl(label, c1, c2, c3, rows, hint) {
    return { isTbl: true, label, c1, c2, c3, hint: hint || '', rows: rows.map(r => ({ n: r[0], a: r[1], b: r[2] || '', bc: r[3] || '#fff', ff: r[4] ? "'JB',ui-monospace,monospace" : 'inherit', em: r[5] || '', bg: r[6] || 'rgba(255,255,255,.07)', click: r[7] || (() => {}), cur: r[7] ? 'pointer' : 'default' })) };
  }
  note(h, b, label) { return { isNote: true, h, b, label: label || '' }; }
  sec(k) {
    const s = this.sim, T = (kk, v, u, su) => ({ k: kk, v, u: u || '', s: su || '' });
    const G = '#8DF3C4', A = '#FCD98A', R = '#FFAFAF', I = '#A9CBFF', Wt = '#fff';
    const cpu = Math.round(s.cpu), gpu = Math.round(s.gpu), hot = s.hot.toFixed(1);
    const netS = s.net >= 1000 ? (s.net / 1000).toFixed(1) + ' MB/s' : Math.round(s.net) + ' KB/s';
    if (this.props.firstRun && this.E[k]) return { tiles: [], mods: [this.note('FATHOM was installed 20 minutes ago.', this.E[k])], act: k === 'home' || k === 'scan' ? { t: 'Run the first Deep Scan' } : null };
    switch (k) {
      case 'home': return { tiles: [T('Actually free', '74.2', 'GB', 'of 494.38 · 85% used'), T('CPU', cpu + '%', '', 'load across 8 cores'), T('Memory', '12.3', 'GB', '77% of 16 GB · pressure normal'), T('Hottest', hot + '°', '', 'CPU performance cluster')], mods: [
        { isGrid: true, label: 'Every section, one number each', items3: [
          { t: 'Deep Scan', v: '2 h ago', s: '132.6 GB truly freeable', go: () => this.go('scan') },
          { t: 'Storage', v: '74.2 GB', s: 'actually free', go: () => this.go('storage') },
          { t: 'Timeline', v: '+9.6 GB', s: 'last 30 days', go: () => this.go('timeline') },
          { t: 'Reclaim', v: '101.0 GB', s: 'selected, dry run', go: () => this.go('reclaim') },
          { t: 'Endurance', v: '3%', s: 'consumed · decades left', go: () => this.go('endurance') },
          { t: 'Attribution', v: '96.4%', s: 'of today explained', go: () => this.go('attrib') },
          { t: 'GPU', v: gpu + '%', s: '10 cores', go: () => this.go('gpu') },
          { t: 'Network', v: netS, s: 'down, Wi-Fi en0', go: () => this.go('network') },
          { t: 'Sensors', v: s.pwr.toFixed(1) + ' W', s: 'total system', go: () => this.go('sensors') },
          { t: 'Bluetooth', v: '3', s: 'devices · 1 will not say', go: () => this.go('bt') },
          { t: 'Applications', v: '3', s: 'vital updates', go: () => this.go('apps') },
          { t: 'SSD Health', v: '97%', s: 'unchanged for nine weeks', go: () => this.go('ssd') } ] },
        { isFeed: true, label: 'Worth a look', items2: [
          { c: A, t: 'Xcode left 48.2 GB behind', p: 'Six branches rebuilt DerivedData on Tuesday. All of it frees.', v: '48.2 GB', vc: G },
          { c: A, t: '37 local snapshots, 42.3 GB', p: 'macOS lets these reach 80% of the disk. Deleting files frees nothing until they go.', v: '42.3 GB', vc: A },
          { c: A, t: 'Time Machine has not run in 9 days', p: 'The backup disk has not been seen since 10 August. Snapshots are piling up in its place.', v: '9 days', vc: A },
          { c: I, t: 'Docker holds 62.4 GB, frees none', p: 'Sparse image. Its logical size is fiction. Compaction is the only route.', v: '0 GB', vc: Wt } ] },
        this.note('Nothing is wrong. Four things are worth a look.', 'A full disk is not an emergency. Every number above links to the screen that produced it, and every screen shows both numbers: on disk, and freed if deleted.') ], act: { t: 'Deep Scan', go: () => this.go('scan') } };
      case 'scan': return { tiles: [T('Truly freeable', '132.6', 'GB', 'of 420.2 GB used'), T('Snapshots', '42.3', 'GB', 'across 37 local snapshots'), T('SSD health', '97%', '', 'unchanged for nine weeks'), T('FileVault', 'On', '', 'this volume is encrypted')], mods: [
        this.tbl('Everything found, both numbers', 'Item', 'On disk', 'Freed if deleted', [
          ['~/Library/Developer/Xcode/DerivedData', '48.2 GB', '48.2 GB', G, 1],
          ['~/Library/Caches', '21.6 GB', '21.6 GB', G, 1],
          ['~/Movies/Final Cut Backups', '34.9 GB', '31.2 GB', G, 1],
          ['/Volumes/.timemachine snapshots', '42.3 GB', '42.3 GB', A, 1, 'needs care'],
          ['~/Library/Containers/com.docker.docker', '62.4 GB', '0 GB', A, 1, 'sparse'],
          ['~/Pictures/Photos Library.photoslibrary', '88.1 GB', '0 GB', R, 1, 'in use'] ], 'The second column is the one no other tool shows you.'),
        this.note('Both numbers, before you touch anything.', 'One pass over every volume, 4 m 12 s. The gap between the columns is APFS doing its job: clones, snapshots and sparse files mean size on disk is not what deletion returns.') ], act: { t: 'Reclaim 132.6 GB', go: () => this.go('reclaim') } };
      case 'cpu': return { tiles: [T('Total load', cpu + '%', '', 'system ' + Math.round(cpu * .3) + '% · user ' + Math.round(cpu * .7) + '% · idle ' + (100 - cpu) + '%'), T('Load average', '2.84', '', '5 min 2.31 · 15 min 2.02'), T('P-cluster', '3,480', 'MHz', '4 performance cores'), T('E-cluster', '2,424', 'MHz', '4 efficiency cores')], mods: [
        this.sp('cpu', 100, 'Total load, last 60 seconds'),
        { isCores: true, label: 'Load per core', bars: s.cores.map((c, i) => ({ l: i < 4 ? 'E' + (i + 1) : 'P' + (i - 3), h: Math.round(c) + '%', v: Math.round(c) + '%' })) },
        this.tbl('Busiest processes', 'Process', 'CPU', 'Energy', [
          ['WindowServer', '8.4%', '3.1'], ['Safari', '6.1%', '2.4'], ['Xcode', '4.9%', '4.2'], ['mds_stores', '2.2%', '0.8'], ['coreaudiod', '1.1%', '0.3'] ]),
        this.note('The efficiency cores are carrying most of this.', 'That is the scheduler doing its job, not a problem. We show all eight because an average would hide which cluster is actually working.') ], act: null };
      case 'gpu': return { tiles: [T('Utilisation', gpu + '%', '', 'render ' + gpu + '% · tiler ' + Math.round(gpu * .45) + '%'), T('Neural Engine', '0%', '', 'idle, as it usually is'), T('Frame rate', '60', 'fps', 'compositor, not any one app'), T('GPU power', (s.gpu * .05 + .4).toFixed(1), 'W', 'of ' + s.pwr.toFixed(1) + ' W total')], mods: [
        this.sp('gpu', 100, 'Utilisation, last 60 seconds'),
        this.note('The Neural Engine reads 0% almost always.', 'It only wakes for Core ML workloads, so on most Macs it is a 16-core block of silicon doing nothing. We report it because you paid for it, not because it will ever be interesting.') ], act: null };
      case 'mem': return { tiles: [T('Used', '12.3', 'GB', '77% of 16 GB'), T('Pressure', 'Normal', '', 'macOS\u2019s word for it, not ours'), T('Compressed', '2.3', 'GB', 'held in RAM, costs CPU not disk'), T('Swap written', '6.2', 'GB', 'on disk, and it wears the disk')], mods: [
        { isSeg: true, label: 'Composition', segs: [ { w: '46.3%', bg: 'rgba(255,255,255,.92)' }, { w: '16.3%', bg: '#FCD98A' }, { w: '14.4%', bg: '#FF9F9F' }, { w: '23%', bg: 'rgba(255,255,255,.22)' } ], leg: [ { bg: 'rgba(255,255,255,.9)', t: 'App 7.4 GB' }, { bg: '#FCD98A', t: 'Wired 2.6 GB' }, { bg: '#FF9F9F', t: 'Compressed 2.3 GB' }, { bg: 'rgba(255,255,255,.3)', t: 'Free 3.7 GB' } ] },
        this.tbl('Largest consumers', 'Process', 'Memory', 'Compressed', [
          ['Safari', '3.2 GB', '0.6 GB'], ['Xcode', '2.8 GB', '0.4 GB'], ['Figma', '1.9 GB', '0.5 GB'], ['WindowServer', '1.1 GB', '0.1 GB'], ['kernel_task', '0.9 GB', '—'] ]),
        this.note('Pressure says normal. Swap says 6.2 GB.', 'Both readings are correct and they answer different questions. Pressure asks whether the system is struggling right now. Swap records what it already spent on disk to avoid struggling. Only the second one is written to an SSD you cannot replace.') ], act: null };
      case 'sensors': return { tiles: [T('Total system', s.pwr.toFixed(1), 'W', 'CPU ' + (s.cpu * .05).toFixed(1) + ' · GPU ' + (s.gpu * .05).toFixed(1) + ' · RAM 0.9'), T('Hottest', hot, '°C', 'CPU performance cluster'), T('SSD', '41.2', '°C', '106 °F, NAND proximity'), T('Fan', '—', '', 'this Mac has no fan')], mods: [
        this.sp('pwr', 16, 'Package power, last 60 seconds'),
        this.tbl('Temperature', 'Sensor', '', 'Reading', [
          ['CPU efficiency core 1', '', '38.4 °C'], ['CPU performance core 1', '', hot + ' °C'], ['Average GPU', '', (s.hot - 2.1).toFixed(1) + ' °C'], ['Memory proximity', '', '37.2 °C'], ['NAND', '', '41.2 °C'], ['Airport', '', '35.8 °C'] ]),
        this.tbl('Battery', 'Reading', '', 'Value', [
          ['Health', '', '91%'], ['Cycle count', '', '214'], ['Charge', '', '68% · not charging'], ['Temperature', '', '31.4 °C'] ]),
        this.note('The fan row reads a dash because there is no fan.', 'This MacBook Air is passively cooled. Where a sensor does not exist on this model we leave the dash rather than interpolating a plausible number from its neighbours.') ], act: null };
      case 'network': return { tiles: [T('Down', netS, '', 'peak today 42.6 MB/s'), T('Up', Math.round(s.up) + ' KB/s', '', 'peak today 1.9 MB/s'), T('Latency', '18', 'ms', 'jitter 2 ms'), T('Link', '866', 'Mbps', 'Wi-Fi 802.11ax, status up')], mods: [
        this.sp('net', 5000, 'Throughput, last 60 seconds'),
        this.tbl('Interface', 'Detail', '', 'Value', [
          ['Local address', '', '192.168.1.84'], ['Public address', '', '193.19.109.117 · US'], ['DNS server', '', '192.168.1.1'], ['Physical address', '', 'f4:d4:88:6a:2c:1e', 1], ['Total downloaded', '', '1.84 TB'], ['Total uploaded', '', '212.40 GB'] ]),
        this.note('There is no per-process breakdown here.', 'macOS does not attribute traffic to processes in a way we would stand behind. Little Snitch does it properly with a network extension, and we would rather send you there than guess.') ], act: null };
      case 'bt': return { tiles: [T('Paired', '3', '', 'devices'), T('Connected', '2', '', 'right now'), T('Codec', 'AAC', '', 'AirPods Pro, active')], mods: [
        { isDevs: true, label: 'Devices', rows2: [
          { n: 'AirPods Pro', w: '87%', v: '87%', op: 1, fs: '13px', fst: 'normal', fw: 600 },
          { n: 'Magic Mouse', w: '64%', v: '64%', op: 1, fs: '13px', fst: 'normal', fw: 600 },
          { n: 'K68 BT5.0 keyboard', w: '0%', v: 'does not report', op: .5, fs: '11px', fst: 'italic', fw: 400 } ] },
        this.note('The keyboard row is blank because the keyboard will not say.', 'Plenty of third-party Bluetooth peripherals never implement the battery service. Showing an estimate there would be a guess wearing a percentage sign.') ], act: null };
      case 'storage': return { tiles: [T('Actually free', '74.2', 'GB', 'the true number, right now'), T('Finder says', '118.6', 'GB', 'it counts purgeable it may not release'), T('Reclaimable', '+132.6', 'GB', 'would take you to 206.8 GB'), T('Purgeable', '44.4', 'GB', '31 GB cannot purge for a write')], mods: [
        { isMap: true, label: 'Where 420.2 GB sits — area is size on disk', rects: [
          { n: 'Developer', v: '142.2 GB · 69.8 frees', l: '0%', t: '0%', w: '33.8%', h: '100%', bg: 'rgba(255,255,255,.22)' },
          { n: 'Applications', v: '94.7 GB', l: '33.8%', t: '0%', w: '34.3%', h: '65.7%', bg: 'rgba(255,255,255,.17)' },
          { n: 'Photos', v: '88.1 GB · in use', l: '68.1%', t: '0%', w: '31.9%', h: '65.7%', bg: 'rgba(255,255,255,.14)' },
          { n: 'Library', v: '66.6 GB · 21.6 frees', l: '33.8%', t: '65.7%', w: '46.2%', h: '34.3%', bg: 'rgba(255,255,255,.11)' },
          { n: 'System', v: '12.1 GB', l: '80%', t: '65.7%', w: '8.4%', h: '34.3%', bg: 'rgba(255,255,255,.09)' },
          { n: 'Other', v: '16.5 GB', l: '88.4%', t: '65.7%', w: '11.6%', h: '34.3%', bg: 'rgba(255,255,255,.07)' } ] },
        this.note('Finder says 118.6 GB. The honest answer is 74.2.', 'Finder counts purgeable space it may not be able to release. 31 GB of that cannot be purged for a write on this volume at all. We show the number a write would actually see.') ], act: { t: 'Explore the tree', go: () => this.go('explore') } };
      case 'timeline': return { tiles: [T('Net, 7 days', '+2.8', 'GB', 'writes 68.4 · deletes 65.6'), T('Net, 30 days', '+9.6', 'GB', 'steady, no spikes'), T('History', '142', 'days', 'recording since 29 March'), T('Busiest day', 'Tue', '', '+6.2 GB, Xcode rebuilds')], mods: [
        { isDays: true, label: 'Last 7 days — grew and shrank', days: [
          { b: 'Wed', upH: '18%', dnH: '30%', v: '−1.1' }, { b: 'Thu', upH: '22%', dnH: '64%', v: '−9.4' }, { b: 'Fri', upH: '48%', dnH: '8%', v: '+6.2' }, { b: 'Sat', upH: '12%', dnH: '10%', v: '+0.3' }, { b: 'Sun', upH: '31%', dnH: '6%', v: '+4.0' }, { b: 'Mon', upH: '20%', dnH: '14%', v: '+1.4' }, { b: 'Tue', upH: '44%', dnH: '18%', v: '+1.4' } ] },
        this.note('142 days of history, and it admits its gaps.', 'The record starts 29 March, the day FATHOM was installed. In the year view the three days before that are drawn empty rather than smoothed over. A chart that hides its own blind spots is worse than no chart.') ], act: { t: 'Open Attribution', go: () => this.go('attrib') } };
      case 'explore': return { tiles: [T('Nodes', '1,184,203', '', 'indexed in the last pass'), T('Deepest', '14', 'levels', '~/Library, as always'), T('Largest file', '8.4', 'GB', 'a Final Cut render')], mods: [
        this.tbl('Every node, both numbers', 'Item', 'On disk', 'Freed if deleted', [
          ['~/Pictures/Photos Library.photoslibrary', '88.1 GB', '0 GB', R, 1, 'in use'],
          ['~/Library/Containers/com.docker.docker', '62.4 GB', '0 GB', A, 1, 'sparse'],
          ['~/Library/Developer/Xcode/DerivedData', '48.2 GB', '48.2 GB', G, 1],
          ['/Volumes/.timemachine snapshots', '42.3 GB', '42.3 GB', A, 1, 'needs care'],
          ['~/Movies/Final Cut Backups', '34.9 GB', '31.2 GB', G, 1],
          ['~/Library/Caches', '21.6 GB', '21.6 GB', G, 1],
          ['~/Downloads', '9.8 GB', '9.8 GB', G, 1] ], 'Hold ⌥ to swap every number. Sorted by the one nobody else shows you.') ], act: { t: 'Select 101.0 GB', go: () => this.go('reclaim') } };
      case 'reclaim': {
        const RS = this.state.rsel;
        const RD = [ ['derived', 'Xcode DerivedData', 48.2, 'one rebuild, ~8 min'], ['caches', 'Package caches', 21.6, 're-downloads on install'], ['fcp', 'Final Cut backups > 90 days', 31.2, 'none identified'], ['snap', 'Thin local snapshots', 42.3, '37 restore points'], ['logs', 'Rotate system logs', 3.1, '30 days of diagnostics'] ];
        const tot = RD.reduce((a, r) => a + (RS[r[0]] ? r[2] : 0), 0), totS = tot.toFixed(1);
        return { tiles: [T('Selected', totS, 'GB', RD.filter(r => RS[r[0]]).length + ' of ' + RD.length + ' rules'), T('After', (74.2 + tot).toFixed(1), 'GB', 'free, if you proceed'), T('Destination', 'Trash', '', 'nothing is deleted'), T('Rules', 'Readable', '', 'every one, in plain text')], mods: [
        this.tbl('Dry run — click a rule to include it', 'Rule', 'Frees', 'Cost', RD.map(r => [r[1], r[2].toFixed(1) + ' GB', r[3], RS[r[0]] ? G : A, 0, RS[r[0]] ? 'selected' : 'not selected', RS[r[0]] ? 'rgba(141,243,196,.10)' : 'rgba(255,255,255,.07)', () => this.setState(st => ({ rsel: { ...st.rsel, [r[0]]: !st.rsel[r[0]] } }))])),
        this.note('Nothing is deleted.', 'Everything goes to the Trash, and every rule is one you can read. The cost column is stated before anything runs, not after.') ], act: { t: 'Move ' + totS + ' GB to Trash' } }; }
      case 'endurance': return { tiles: [T('Consumed', '3%', '', 'in 2,930 power-on hours'), T('Written', '38.4', 'TB', 'lifetime'), T('Per hour', '13.1', 'GB', 'about 30% swap'), T('Projection', '97,600', 'hours', 'linear · decades, not years')], mods: [
        { isChain: true, label: 'The arithmetic', items: [
          { l: 'Written', v: '38.4 TB', s: 'lifetime', arrow: true }, { l: 'Per hour', v: '13.1 GB', s: 'about 30% swap', arrow: true }, { l: 'Consumed', v: '3%', s: 'in 2,930 hours', arrow: true }, { l: 'Remaining', v: 'decades', s: 'not years', arrow: false } ] },
        this.note('Your SSD is fine, and most of what you have read about Apple silicon SSD wear is wrong.', 'This drive has written 38.4 TB and given up 3% of its endurance. Straight-line, that is 97,600 power-on hours against 2,930 so far. We are not going to print a date, because Apple does not publish a TBW rating for the AP0512Z and any specific date would be a guess dressed as a forecast. If the rate changes, the digest will tell you. Until then, this screen is allowed to be boring.') ], act: { t: 'What would move the number' } };
      case 'attrib': return { tiles: [T('Written today', '9.8', 'GB', 'across 41 processes'), T('Explained', '96.4%', '', '0.35 GB we cannot attribute'), T('Repeat offender', 'Xcode', '', '5 of the last 7 days'), T('Watchers', '2', '', 'active, zero cost when quiet')], mods: [
        this.tbl('Who wrote it', 'Process', 'Written', 'Share', [
          ['com.apple.dt.Xcode', '5.2 GB', '53.1%', G, 1], ['kernel_task · swap', '1.9 GB', '19.4%', A, 1], ['com.apple.Safari', '1.4 GB', '14.3%', G, 1], ['com.apple.Photos', '0.9 GB', '9.2%', G, 1], ['unattributed', '0.35 GB', '3.6%', R, 1, '', 'rgba(255,175,175,.11)'] ]),
        this.note('That last row is the honest one.', '0.35 GB was written by something we could not trace to a process, most likely a system daemon writing through a path FSEvents does not name. We give it its own line rather than distributing it across the rows above to make the percentages look tidy.') ], act: { t: 'Watch for repeats' } };
      case 'digest': return { tiles: [T('Next', 'Sunday', '', '09:00, local time'), T('Sent', '19', '', 'digests since install'), T('Quiet weeks', '7', '', 'it said so, in one line')], mods: [
        { isDig: true, label: 'This week\u2019s preview', date: 'Sunday, 16 August · week 33', l1: '2.8 GB fuller', rows4: [
          { n: 'Xcode DerivedData', v: '+5.2 GB', c: '#B42318' }, { n: 'Docker images', v: '+1.8 GB', c: '#B42318' }, { n: 'You emptied the Trash on Friday', v: '−8.4 GB', c: '#067647' } ], l2: 'Your SSD is still at 97% health, unchanged for nine weeks. At the rate this Mac is actually used, that is decades, not years.' },
        { isTogs: true, label: 'Delivery', rows3: [
          { b: 'Send on', s: 'Sunday at 09:00, local time', tbg: '#5CE6A8', tx: '19.5px' }, { b: 'Stay silent when nothing changed', s: 'Recommended', tbg: '#5CE6A8', tx: '19.5px' } ] },
        this.note('One notification a week, and it is allowed to say nothing.', 'If the week was quiet the digest says so in one line and stops. It never invents a finding to justify arriving. Every number links to the evidence that produced it.') ], act: null };
      case 'apps': return { tiles: [T('Footprint', '94.7', 'GB', 'across 136 applications'), T('Leftovers', '4.8', 'GB', 'from 19 apps no longer installed'), T('Unused a year', '14.2', 'GB', '8 apps, last opened before Aug 2025'), T('Vital updates', '3', '', 'security fixes, of 7 available')], mods: [
        this.tbl('Largest, counting all six places', 'Application', 'App itself', 'Everything else', [
          ['Xcode', '31.6 GB', '48.2 GB', A, 0, 'DerivedData'], ['Final Cut Pro', '4.1 GB', '34.9 GB', A, 0, 'backups'], ['Docker', '1.2 GB', '62.4 GB', A, 0, 'sparse image'], ['Figma', '0.9 GB', '2.2 GB', Wt, 0, 'caches'], ['Safari', '0.2 GB', '3.4 GB', Wt, 0, 'caches'] ]),
        this.note('Four apps ship the same Electron build.', '1.4 GB of identical frameworks, four times over. We count it once per app because that is what the disk does, and we name it here because nobody else will.') ], act: { t: 'Review 19.0 GB' } };
      case 'cloud': return { tiles: [T('Really on disk', '88.4', 'GB', 'iCloud Drive claims 214.7 GB'), T('Cloud only', '126.3', 'GB', 'never downloaded'), T('Freed by evicting', '+61.2', 'GB', '27.2 GB is pinned and stays')], mods: [
        { isSeg: true, label: 'Claim vs occupancy', segs: [ { w: '41%', bg: 'rgba(255,255,255,.9)' }, { w: '59%', bg: 'rgba(255,255,255,.26)' } ], leg: [ { bg: 'rgba(255,255,255,.9)', t: 'Downloaded 88.4 GB' }, { bg: 'rgba(255,255,255,.3)', t: 'Cloud only 126.3 GB' } ] },
        this.note('Evicting is not deleting.', 'The file stays in iCloud and comes back when you open it. What you lose is offline access, and the wait. Finder shows you the claim, not the occupancy.') ], act: { t: 'Evict 61.2 GB' } };
      case 'maint': return { tiles: [T('Tasks', '6', '', 'each states its cost first'), T('Selected', '2', '', 'frees 45.4 GB'), T('Riskiest', 'Spotlight', '', 'search degraded 2–4 hours')], mods: [
        this.tbl('Each task states its cost before it runs', 'Task', 'Takes', 'Cost', [
          ['Thin local snapshots', 'frees 42.3 GB', '37 restore points', A],
          ['Rotate system logs', 'frees 3.1 GB', '30 days of diagnostics', A],
          ['Rebuild Spotlight index', '2–4 hours', 'search degraded meanwhile', A],
          ['Flush DNS cache', 'instant', 'may reconnect the network', Wt],
          ['Rebuild Launch Services', 'under a minute', 'fixes wrong app icons', Wt],
          ['Verify startup volume', '8–15 minutes', 'read only, safe to cancel', G] ]),
        this.note('Costs first, always.', 'Caches, logs, snapshots and the tasks macOS runs badly. Nothing here runs until you have read what it takes from you.') ], act: { t: 'Run 2 selected' } };
      case 'ssd': return { tiles: [T('Health', '97%', '', 'available spare 100%'), T('Written', '38.4', 'TB', 'read 51.2 TB · ratio 1.33:1'), T('Power on', '2,930', 'hours', '410 power cycles'), T('Unsafe shutdowns', '12', '', 'media errors 0 · no warning')], mods: [
        this.tbl('What the controller itself reports', 'Reading', '', 'Value', [
          ['Model', '', 'APPLE SSD AP0512Z', Wt, 1], ['Interface', '', 'Apple Fabric · disk3s1s1', Wt, 1], ['Percentage used', '', '3%'], ['Available spare', '', '100%'], ['Media errors', '', '0'], ['Critical warning', '', 'none'], ['FileVault', '', 'On'] ]),
        this.note('Read only. Nothing here can be changed by this app.', 'Every value comes from the NVMe SMART log the controller keeps for itself. Where this model does not publish a field, the row is absent rather than estimated.') ], act: { t: 'Open Endurance', go: () => this.go('endurance') } };
      case 'menubar': default: return { tiles: [T('Cost', '0.2%', 'CPU', 'measured, four items shown'), T('Energy', '2.1', '', 'impact while visible'), T('Refresh', '1', 'Hz', 'stops when hidden'), T('Height', '22', 'pt', 'the height macOS gives it')], mods: [
        { isMbar: true, label: 'Live preview — actual size', free: '74.2', hot: Math.round(s.hot) + '°', net: s.net >= 1000 ? (s.net / 1000).toFixed(1) : String(Math.round(s.net)), cpu: String(cpu), time: new Date().toTimeString().slice(0, 5) },
        { isTogs: true, label: 'Items', rows3: [
          { b: 'Free space', s: 'The true number, not Finder\u2019s', tbg: '#5CE6A8', tx: '19.5px' },
          { b: 'Hottest sensor', s: 'Across all 22 published', tbg: '#5CE6A8', tx: '19.5px' },
          { b: 'Network throughput', s: 'Down only, to save width', tbg: '#5CE6A8', tx: '19.5px' },
          { b: 'CPU load', s: 'Total across all eight cores', tbg: '#5CE6A8', tx: '19.5px' },
          { b: 'Public IP and country', s: 'Shown in the app, not the strip', tbg: 'rgba(255,255,255,.16)', tx: '2.5px' },
          { b: 'Endurance dot', s: 'Only appears if the forecast moves', tbg: 'rgba(255,255,255,.16)', tx: '2.5px' } ] },
        this.note('Every item costs width you cannot get back.', 'And a sample you did not need. The widget refreshes once a second while the menu bar is open and stops entirely when it is hidden. Measured cost of the four above: 0.2% CPU, energy impact 2.1.') ], act: null };
    }
  }
  renderVals() {
    const k = this.state.k, w = this.W[k] || this.W.home;
    const mix = 'color-mix(in srgb,' + w[2] + ' 82%,#fff 7%)';
    const bgGrad = 'radial-gradient(92% 72% at 50% 118%,' + mix + ' 0%,transparent 64%),radial-gradient(130% 90% at 85% -12%,rgba(0,0,0,.42) 0%,transparent 52%),linear-gradient(177deg,' + w[0] + ' 0%,' + w[1] + ' 58%,' + w[2] + ' 106%)';
    const G = [['SURFACE', ['menubar', 'digest']], ['OVERVIEW', ['home', 'scan']], ['SYSTEM', ['cpu', 'gpu', 'mem', 'sensors', 'network', 'bt']], ['STORAGE', ['storage', 'timeline', 'explore', 'reclaim', 'endurance', 'attrib', 'apps', 'cloud', 'maint', 'ssd']]];
    const navItems = [];
    G.forEach(g => {
      navItems.push({ isH: true, isA: false, label: g[0] });
      g[1].forEach(kk => {
        const on = kk === k;
        navItems.push({ isH: false, isA: true, label: this.TT[kk], ic: 'assets/icons/' + kk + '.svg', go: () => this.go(kk), bg: on ? 'linear-gradient(180deg,rgba(255,255,255,.26),rgba(255,255,255,.13))' : 'transparent', col: on ? '#fff' : 'rgba(255,255,255,.62)', fw: on ? 600 : 400, sh: on ? 'inset 0 1px 0 rgba(255,255,255,.3),0 8px 18px rgba(0,0,0,.22)' : 'none' });
      });
    });
    const d = this.sec(k);
    return {
      bgGrad, navItems, fref: this.fr, cref: this.cr,
      dispFont: ({ 'Archivo semi-expanded': "'Archivo',sans-serif", 'Bricolage (design system)': "'Bricolage',sans-serif", 'Technical grotesk': "'Space Grotesk',sans-serif" })[this.props.typeface] || "'Archivo',sans-serif",
      secTitle: this.TT[k], secSub: this.SUB[k], secLabel: this.TT[k] + ' — enhanced',
      tiles: d.tiles, mods: d.mods,
      actTxt: d.act ? d.act.t : '', actGo: d.act && d.act.go ? d.act.go : () => {},
      footCpu: Math.round(this.sim.cpu) + '% CPU',
      showCur: this.props.showCurrent === true,
      showOb: this.state.ob,
      obSkip: () => this.dismiss(false), obGo: () => this.dismiss(true)
    };
  }
}



