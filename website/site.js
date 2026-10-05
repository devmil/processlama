/* ProcessLama website behaviour. Everything here is an enhancement: the pages
   read and link correctly without it. */
(() => {
  "use strict";

  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

  /* Hero: a drawn process tree on a pulse line, with the Lama standing on
     that line. Branches sway, leaves spawn and terminate, and activity
     travels back to the root, where it leaves as a beat along the line. A
     beat passing under the Lama makes it hop. Pointing at a node lights the
     path to its ancestors. */
  function heroTree(canvas) {
    const hero = canvas.parentElement;
    const ctx = canvas.getContext("2d");
    const counter = document.querySelector("[data-tree-count]");
    const lama = hero.querySelector("[data-hero-lama]");

    const NAMES = [
      "launchd", "WindowServer", "Finder", "Dock", "Safari", "Code", "rust-analyzer",
      "zsh", "cargo", "dart", "flutter", "Terminal", "sshd", "node", "postgres",
      "systemd", "kworker", "pipewire", "gnome-shell", "Xwayland", "bash", "git",
      "clangd", "mdworker", "cfprefsd", "dbus-daemon", "NetworkManager", "journald",
      "explorer", "svchost", "python3", "rustc", "make", "tmux", "vim", "curl",
    ];
    const KIDS = [[5, 5], [2, 3], [1, 3], [1, 2], [0, 1]];
    const SPREAD = [2.3, 1.25, 1.1, 1.0, 0.9];
    const LENGTH = [0.2, 0.17, 0.13, 0.1, 0.075, 0.055];
    const MAX_DEPTH = 5;

    /* Colours are Meridian tokens read from the page, so the drawing follows
       light and dark: teal branches, amber leaves, the accent for the path
       being followed, success for a spawn and danger for an exit. */
    let paint = {};
    function readPaint() {
      const style = getComputedStyle(hero);
      const token = (name) => style.getPropertyValue(name).trim();
      paint = {
        branch: token("--tree-branch"),
        leaf: token("--tree-leaf"),
        node: token("--ink-muted"),
        lit: token("--tree-lit") || token("--accent"),
        line: token("--prop") || token("--tree-branch"),
        spawn: token("--success"),
        exit: token("--danger"),
        raised: token("--raised"),
        ink: token("--ink"),
        muted: token("--ink-muted"),
        edge: token("--line-strong"),
      };
    }
    readPaint();
    const GROW_MS = 900;
    const FADE_MS = 800;

    /* A seeded generator keeps the first tree identical on every visit. */
    let seed = 20260930;
    const seeded = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296;
    const between = (range, random) => range[0] + Math.floor(random() * (range[1] - range[0] + 1));

    let nextPid = 1;
    function makeNode(parent, depth, rel, born, random) {
      const node = {
        parent, depth, rel, born,
        dead: 0,
        length: LENGTH[depth] * (0.75 + random() * 0.5),
        phase: random() * Math.PI * 2,
        bend: (random() - 0.5) * 0.4,
        cpu: random() * random(),
        target: 0,
        name: depth === 0 ? NAMES[0] : NAMES[1 + Math.floor(random() * (NAMES.length - 1))],
        pid: nextPid,
        kids: [],
        weight: 1,
        x: 0, y: 0, px: 0, py: 0, cx: 0, cy: 0, angle: 0, grown: 0,
      };
      node.target = node.cpu;
      nextPid += 1 + Math.floor(random() * 37);
      return node;
    }

    function sprout(node) {
      if (node.depth >= MAX_DEPTH) return;
      const count = between(KIDS[node.depth], seeded);
      for (let index = 0; index < count; index += 1) {
        const fan = count === 1 ? 0 : (index / (count - 1) - 0.5) * SPREAD[node.depth];
        const rel = fan + (seeded() - 0.5) * 0.28;
        const born = (node.depth + 1) * 260 + seeded() * 320;
        const child = makeNode(node, node.depth + 1, rel, born, seeded);
        node.kids.push(child);
        sprout(child);
      }
    }

    const root = makeNode(null, 0, 0, 0, seeded);
    sprout(root);

    let nodes = [];
    function flatten() {
      nodes = [];
      const visit = (node) => {
        nodes.push(node);
        node.weight = node.kids.length ? 0 : 1;
        for (const kid of node.kids) node.weight += visit(kid);
        return node.weight;
      };
      visit(root);
      if (counter) counter.textContent = String(nodes.filter((node) => !node.dead).length);
    }
    flatten();

    let width = 0;
    let height = 0;
    let scale = 1;
    let rootX = 0;
    let rootY = 0;
    let beatScale = 1;
    /* The Lama's feet on the pulse line, read from its box (styles.css). */
    let feet = { left: 0, right: 0, centre: 0 };

    function resize() {
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      width = hero.clientWidth;
      height = hero.clientHeight;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      const narrow = width <= 820;
      rootY = height - (parseFloat(getComputedStyle(hero).getPropertyValue("--pulse-base")) || 0);
      if (lama) {
        const box = lama.getBoundingClientRect();
        const origin = hero.getBoundingClientRect();
        /* Legs span 23% to 87% of the 120-unit artwork. */
        feet = {
          left: box.left - origin.left + box.width * 0.23,
          right: box.left - origin.left + box.width * 0.87,
          centre: box.left - origin.left + box.width * 0.55,
        };
      }
      rootX = narrow ? width * 0.34 : Math.min(width * 0.58, feet.left - 120);
      scale = narrow ? Math.min(width * 1.05, 420) : Math.min(height * 0.96, width * 0.5);
      beatScale = narrow ? 1.1 : 1.5;
    }

    function growth(node, time) {
      const eased = 1 - Math.pow(1 - clamp((time - node.born) / GROW_MS, 0, 1), 3);
      return node.dead ? eased * (1 - clamp((time - node.dead) / FADE_MS, 0, 1)) : eased;
    }

    function place(node, px, py, parentAngle, time) {
      const sway = reducedMotion
        ? 0
        : Math.sin(time * 0.0005 + node.phase) * 0.018 + Math.sin(time * 0.00017 + node.depth) * 0.008 * node.depth;
      node.grown = growth(node, time);
      node.angle = parentAngle + node.rel + sway;
      const reach = node.length * scale * node.grown;
      node.px = px;
      node.py = py;
      node.x = px + Math.cos(node.angle) * reach;
      node.y = py + Math.sin(node.angle) * reach;
      node.cx = (px + node.x) / 2 - Math.sin(node.angle) * reach * node.bend;
      node.cy = (py + node.y) / 2 + Math.cos(node.angle) * reach * node.bend;
      for (const kid of node.kids) place(kid, node.x, node.y, node.angle, time);
    }

    function branch(node) {
      ctx.beginPath();
      ctx.moveTo(node.px, node.py);
      ctx.quadraticCurveTo(node.cx, node.cy, node.x, node.y);
      ctx.stroke();
    }

    /* Activity dots that run from a process back toward the root. */
    let pulses = [];
    function stepPulses(delta) {
      if (pulses.length < 16 && Math.random() < 0.05) {
        const node = nodes[Math.floor(Math.random() * nodes.length)];
        if (node.parent && !node.dead && node.grown > 0.95 && Math.random() < 0.25 + node.cpu) {
          pulses.push({ node, along: 0 });
        }
      }
      pulses = pulses.filter((pulse) => {
        pulse.along += (delta * 0.00014) / pulse.node.length;
        while (pulse.along >= 1) {
          pulse.along -= 1;
          pulse.node = pulse.node.parent;
          if (!pulse.node) {
            rootBeat();
            return false;
          }
        }
        return !pulse.node.dead;
      });
    }

    function drawPulses() {
      for (const pulse of pulses) {
        const node = pulse.node;
        const a = 1 - pulse.along;
        const b = pulse.along;
        const x = a * a * node.x + 2 * a * b * node.cx + b * b * node.px;
        const y = a * a * node.y + 2 * a * b * node.cy + b * b * node.py;
        /* Fade in and out at the ends of each segment so dots never pop. */
        const fade = Math.min(1, pulse.along * 4, (1 - pulse.along) * 4 + (pulse.node.parent ? 1 : 0));
        ctx.globalAlpha = 0.14 * fade;
        ctx.fillStyle = paint.branch;
        ctx.beginPath();
        ctx.arc(x, y, 4.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 0.85 * fade;
        ctx.beginPath();
        ctx.arc(x, y, 1.4, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    /* Beats along the pulse line: the app icon's spike, travelling right. */
    const BEAT = [[0, 0], [6, -10], [13, 11], [19, -7], [23, 0]];
    const BEAT_SPEED = 0.26;
    let beats = [];
    let beatClock = 0;
    let lastRootBeat = -1e9;
    let ambientAt = 1800;
    let hopUntil = 0;

    function addBeat(x) {
      beats.push({ x, amp: 0.7 + Math.random() * 0.5 });
    }

    function rootBeat() {
      if (beatClock - lastRootBeat < 1700) return;
      lastRootBeat = beatClock;
      addBeat(rootX);
    }

    function stepBeats(delta) {
      beatClock += delta;
      if (beatClock > ambientAt) {
        ambientAt = beatClock + 3600 + Math.random() * 3000;
        addBeat(-30 * beatScale);
      }
      const centre = BEAT[2][0] * beatScale;
      beats = beats.filter((beat) => {
        const before = beat.x + centre;
        beat.x += delta * BEAT_SPEED;
        const after = beat.x + centre;
        if (lama && before < feet.centre && after >= feet.centre && beatClock > hopUntil) {
          hopUntil = beatClock + 900;
          lama.classList.remove("is-hopping");
          void lama.offsetWidth;
          lama.classList.add("is-hopping");
        }
        return beat.x < width + 40;
      });
    }

    function drawLine() {
      const points = [[0, rootY]];
      const ordered = [...beats].sort((a, b) => a.x - b.x);
      for (const beat of ordered) {
        const edge = clamp(Math.min(beat.x + 40, width - beat.x) / 120, 0, 1);
        for (const [dx, dy] of BEAT) {
          const x = beat.x + dx * beatScale;
          if (x > points[points.length - 1][0]) points.push([x, rootY + dy * beatScale * beat.amp * edge]);
        }
      }
      points.push([width, rootY]);
      ctx.strokeStyle = paint.line;
      ctx.lineJoin = "round";
      for (const [alpha, lineWidth] of [[0.16, 9], [1, 2.6]]) {
        ctx.globalAlpha = alpha;
        ctx.lineWidth = lineWidth;
        ctx.beginPath();
        points.forEach(([x, y], index) => (index ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }

    let pointer = null;
    let focus = null;
    let focusSince = 0;
    let autoFocusAt = 0;
    const setFocus = (node, time) => {
      if (node === focus) return;
      focus = node;
      focusSince = time;
    };
    const introDone = 3200;

    function pickFocus(time) {
      if (pointer) {
        /* Keep the current node while the pointer stays near it. */
        if (focus && !focus.dead && (focus.x - pointer.x) ** 2 + (focus.y - pointer.y) ** 2 < 46 * 46) {
          autoFocusAt = time + 4000;
          return;
        }
        let best = null;
        let bestDistance = 70 * 70;
        for (const node of nodes) {
          const distance = (node.x - pointer.x) ** 2 + (node.y - pointer.y) ** 2;
          if (distance < bestDistance && !node.dead && node.grown > 0.6) {
            best = node;
            bestDistance = distance;
          }
        }
        if (best) {
          setFocus(best, time);
          autoFocusAt = time + 4000;
          return;
        }
      }
      if (time < introDone) return;
      if (time > autoFocusAt || (focus && focus.dead)) {
        /* Keep the automatic label clear of the introduction on the left. */
        const clear = width > 820 ? width * 0.5 : 0;
        const candidates = nodes.filter((node) => node.depth >= 2 && !node.dead && node.grown > 0.95 && node.x > clear);
        setFocus(candidates.length ? candidates[Math.floor(Math.random() * candidates.length)] : null, time);
        autoFocusAt = time + 7000;
      }
    }

    function drawLabel(node) {
      /* A Meridian tooltip: raised surface, float edge, name then figures. */
      const name = node.name;
      const figures = `${node.pid} · ${(node.cpu * 38).toFixed(1)}%`;
      ctx.font = '600 12px "Geist", sans-serif';
      const nameWidth = ctx.measureText(name).width;
      ctx.font = '400 11px "Geist Mono", ui-monospace, monospace';
      const boxWidth = nameWidth + ctx.measureText(figures).width + 30;
      const boxHeight = 26;
      const x = clamp(node.x + 12, 8, width - boxWidth - 8);
      const y = clamp(node.y - boxHeight - 10, 8, height - boxHeight - 8);
      ctx.save();
      ctx.shadowColor = "rgba(0, 0, 0, 0.28)";
      ctx.shadowBlur = 24;
      ctx.shadowOffsetY = 8;
      ctx.fillStyle = paint.raised;
      ctx.beginPath();
      ctx.roundRect(x, y, boxWidth, boxHeight, 8);
      ctx.fill();
      ctx.restore();
      ctx.strokeStyle = paint.edge;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.roundRect(x + 0.5, y + 0.5, boxWidth - 1, boxHeight - 1, 8);
      ctx.stroke();
      ctx.textBaseline = "middle";
      ctx.font = '600 12px "Geist", sans-serif';
      ctx.fillStyle = paint.ink;
      ctx.fillText(name, x + 10, y + boxHeight / 2 + 0.5);
      ctx.font = '400 11px "Geist Mono", ui-monospace, monospace';
      ctx.fillStyle = paint.muted;
      ctx.fillText(figures, x + 20 + nameWidth, y + boxHeight / 2 + 0.5);
    }

    function draw(time) {
      ctx.clearRect(0, 0, width, height);
      ctx.lineCap = "round";
      drawLine();

      ctx.strokeStyle = paint.branch;
      for (const node of nodes) {
        if (node.grown <= 0.01) continue;
        ctx.globalAlpha = 0.78 - node.depth * 0.1;
        ctx.lineWidth = (0.7 + Math.sqrt(node.weight) * 0.52) * Math.min(1, node.grown + 0.2);
        branch(node);
      }
      ctx.globalAlpha = 1;

      const lit = new Set();
      for (let node = focus; node; node = node.parent) lit.add(node);
      const litAlpha = reducedMotion ? 1 : clamp((time - focusSince) / 420, 0, 1);
      ctx.strokeStyle = paint.lit;
      ctx.globalAlpha = litAlpha;
      for (const node of lit) {
        ctx.lineWidth = 1.4 + Math.sqrt(node.weight) * 0.52;
        branch(node);
      }
      ctx.globalAlpha = 1;

      drawPulses();

      for (const node of nodes) {
        if (node.grown <= 0.05) continue;
        const leaf = node.kids.length === 0;
        const radius = (1.3 + node.cpu * 3.1) * node.grown;
        const colour = node.dead ? paint.exit : lit.has(node) && litAlpha > 0.5 ? paint.lit : leaf ? paint.leaf : paint.branch;
        ctx.fillStyle = colour;
        ctx.globalAlpha = 0.13 * node.grown;
        ctx.beginPath();
        ctx.arc(node.x, node.y, radius * 3.4, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = node.grown;
        ctx.beginPath();
        ctx.arc(node.x, node.y, radius, 0, Math.PI * 2);
        ctx.fill();

        /* A ring marks a process that has just spawned. */
        const age = time - node.born;
        if (!reducedMotion && node.born > introDone && age < 1400) {
          ctx.globalAlpha = 0.45 * (1 - age / 1400);
          ctx.strokeStyle = paint.spawn;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(node.x, node.y, 3 + age * 0.012, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      ctx.globalAlpha = 1;

      if (focus && focus.grown > 0.6) {
        ctx.globalAlpha = litAlpha;
        drawLabel(focus);
        ctx.globalAlpha = 1;
      }
    }

    /* Keep the tree alive: spawn a leaf, retire a leaf. */
    let churnAt = introDone + 600;
    function churn(time) {
      if (time < churnAt) return;
      churnAt = time + 2200 + Math.random() * 1800;
      let changed = false;

      for (const node of nodes) {
        if (node.dead && time - node.dead > FADE_MS) {
          node.parent.kids.splice(node.parent.kids.indexOf(node), 1);
          changed = true;
        }
      }

      const alive = nodes.filter((node) => !node.dead);
      if (alive.length < 125) {
        const hosts = alive.filter((node) => node.depth >= 1 && node.depth < MAX_DEPTH && node.kids.length < 4);
        const host = hosts[Math.floor(Math.random() * hosts.length)];
        if (host) {
          const rel = (Math.random() - 0.5) * SPREAD[Math.min(host.depth, SPREAD.length - 1)];
          host.kids.push(makeNode(host, host.depth + 1, rel, time, Math.random));
          changed = true;
        }
      }
      if (alive.length > 85 && Math.random() < 0.7) {
        const leaves = alive.filter((node) => node.depth >= 2 && !node.kids.length && time - node.born > 5000 && node !== focus);
        const leaf = leaves[Math.floor(Math.random() * leaves.length)];
        if (leaf) {
          leaf.dead = time;
          changed = true;
        }
      }
      if (changed) flatten();
    }

    /* Activity eases toward a target that changes now and then, so node
       sizes breathe instead of jittering frame to frame. */
    function wander(delta) {
      for (const node of nodes) {
        if (Math.random() < delta / 2600) node.target = Math.random() ** 2;
        node.cpu += (node.target - node.cpu) * Math.min(1, delta / 900);
      }
    }

    function frameStill() {
      /* One still beat behind the Lama, as in the app icon. */
      beats = lama ? [{ x: feet.right + 6, amp: 1 }] : [];
      place(root, rootX, rootY, -Math.PI / 2, 1e7);
      if (pointer) pickFocus(0);
      draw(0);
    }

    let running = false;
    let visible = true;
    let clock = 0;
    let last = 0;

    function frame(now) {
      if (!running) return;
      const delta = Math.min(now - last, 64);
      last = now;
      clock += delta;
      churn(clock);
      wander(delta);
      place(root, rootX, rootY, -Math.PI / 2, clock);
      stepPulses(delta);
      stepBeats(delta);
      pickFocus(clock);
      draw(clock);
      requestAnimationFrame(frame);
    }

    function setRunning() {
      const should = visible && !document.hidden && !reducedMotion;
      if (should === running) return;
      running = should;
      if (running) {
        last = performance.now();
        requestAnimationFrame(frame);
      }
    }

    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      readPaint();
      if (reducedMotion) frameStill();
    });
    new ResizeObserver(() => {
      resize();
      if (reducedMotion) frameStill();
    }).observe(hero);
    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      setRunning();
    }).observe(hero);
    document.addEventListener("visibilitychange", setRunning);

    hero.addEventListener("pointermove", (event) => {
      const box = canvas.getBoundingClientRect();
      pointer = { x: event.clientX - box.left, y: event.clientY - box.top };
      if (reducedMotion) frameStill();
    });
    hero.addEventListener("pointerleave", () => {
      pointer = null;
    });

    /* The Lama opens with the hello pose, then lifts its chin to the proud
       mark; pointing at it says hello again. */
    if (lama) {
      let settle = setTimeout(() => lama.classList.remove("is-hello"), 2400);
      lama.addEventListener("pointerenter", () => {
        clearTimeout(settle);
        lama.classList.add("is-hello");
      });
      lama.addEventListener("pointerleave", () => {
        settle = setTimeout(() => lama.classList.remove("is-hello"), 500);
      });
      lama.addEventListener("animationend", () => lama.classList.remove("is-hopping"));
    }

    /* Between beats the Lama gets up to things of its own (lama-antics.js,
       from the brand repository). Tapping it plays a gag; one of them is a
       stomp that sends a burst of beats down the pulse line. */
    if (lama && window.LamaAntics) {
      LamaAntics.attach(lama, {
        base: "assets/lama/",
        colors: ["#4C82FB", "#8AF0C6", "#FFF8EB"],
        taps: {
          stomp: async (antic) => {
            await antic.move("bigHop");
            for (let i = 0; i < 3 && antic.live(); i += 1) {
              beats.push({ x: feet.right - BEAT[2][0] * beatScale, amp: 1.3 - i * 0.2 });
              await antic.wait(180);
            }
          },
        },
      });
    }

    resize();
    if (reducedMotion) frameStill();
    setRunning();
  }

  /* The window sketch. It mirrors the app's widgets: rows with avatars,
     descendant counts, CPU sparklines and meters, tree totals, the
     Tree/Process switch, metric tiles and 60-bar history charts. Numbers are
     made up; they tick once a second like the app's default polling. */
  function windowSketch(figure) {
    const SLOTS = 60;
    const app = figure.querySelector(".app-window");
    const list = figure.querySelector("[data-demo-rows]");
    const search = figure.querySelector("[data-demo-search]");
    const matches = figure.querySelector("[data-demo-matches]");
    const lock = figure.querySelector("[data-demo-lock]");
    const status = figure.querySelector("[data-demo-status]");
    const state = figure.querySelector("[data-demo-state]");
    const count = figure.querySelector("[data-demo-count]");
    const field = (name) => figure.querySelector(`[data-i="${name}"]`);
    const liveStatus = status.textContent;
    const svg = (id) => `<svg class="icon" aria-hidden="true"><use href="#${id}"/></svg>`;

    /* The app's formatters (process_explorer_screen.dart). */
    const percent = (value) => (value <= 0 ? "0.0%" : `${value.toFixed(value >= 10 ? 0 : 1)}%`);
    const bytes = (value) => {
      if (value <= 0) return "0 B";
      const units = ["B", "KB", "MB", "GB", "TB"];
      let unit = 0;
      while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
      }
      return `${value.toFixed(unit ? 1 : 0)} ${units[unit]}`;
    };
    const rate = (value) => `${bytes(Math.round(value))}/s`;

    /* MeridianAvatar: initials on a series colour chosen by a name hash. */
    const AVATAR_ORDER = [0, 1, 5, 4, 6, 3, 2, 7];
    const avatarColour = (name) => {
      let hash = 0;
      for (const char of name.toLowerCase()) hash = (hash * 31 + char.charCodeAt(0)) & 0x7fffffff;
      return `var(--series-${AVATAR_ORDER[hash % AVATAR_ORDER.length] + 1})`;
    };
    const initials = (name) => {
      const parts = name.trim().split(/[\s._@-]+/).filter(Boolean);
      if (!parts.length) return "?";
      return (parts.length === 1 ? parts[0][0] : parts[0][0] + parts[1][0]).toUpperCase();
    };

    /* Samplers: CPU wanders around its base with rare bursts; memory creeps;
       network and storage come in bursts. */
    const KEYS = ["cpu", "mem", "gpu", "out", "in", "read", "write"];
    function sampler(base) {
      const now = { cpu: base.cpu, mem: base.mem, gpu: base.gpu, out: 0, in: 0, read: 0, write: 0 };
      const burst = (level) => (level > 0 && Math.random() < 0.35 ? level * 1024 * Math.random() ** 2 * 3 : 0);
      return () => {
        now.cpu = clamp(now.cpu + (base.cpu - now.cpu) * 0.35 + (Math.random() - 0.5) * base.cpu * 0.5 + (Math.random() < 0.04 ? base.cpu * 1.2 : 0), 0, 400);
        now.mem = Math.max(1, now.mem + (base.mem - now.mem) * 0.1 + (Math.random() - 0.5) * base.mem * 0.004);
        now.gpu = base.gpu ? clamp(now.gpu + (base.gpu - now.gpu) * 0.3 + (Math.random() - 0.5) * base.gpu * 0.4, 0, 100) : 0;
        now.out = burst(base.net * 0.4);
        now.in = burst(base.net);
        now.read = burst(base.io);
        now.write = burst(base.io * 0.3);
        return now;
      };
    }
    const empty = () => Object.fromEntries(KEYS.map((key) => [key, 0]));
    const history = () => Object.fromEntries(KEYS.map((key) => [key, []]));

    const nodes = [];
    function makeNode(row) {
      const data = row.dataset;
      const num = (key) => Number(data[key] || 0);
      const node = {
        row,
        depth: num("depth"),
        name: data.name,
        pid: data.pid,
        threads: data.threads,
        own: sampler({ cpu: num("cpu"), mem: num("mem") * 1048576, gpu: num("gpu"), net: num("net"), io: num("io") }),
        hidden: num("hidden")
          ? sampler({ cpu: num("hiddenCpu"), mem: num("hiddenMem") * 1048576, gpu: num("hiddenGpu"), net: num("hiddenNet"), io: num("hiddenIo") })
          : null,
        hiddenCount: num("hidden"),
        parent: null,
        kids: [],
        now: { process: empty(), tree: empty() },
        past: { process: history(), tree: history() },
        descendants: 0,
        collapsed: false,
        change: null,
      };
      return node;
    }

    function link() {
      const stack = [];
      for (const node of nodes) {
        node.kids = [];
        while (stack.length && stack[stack.length - 1].depth >= node.depth) stack.pop();
        node.parent = stack[stack.length - 1] || null;
        if (node.parent) node.parent.kids.push(node);
        stack.push(node);
      }
    }

    function sample() {
      for (const node of nodes) {
        if (node.change !== "terminated") Object.assign(node.now.process, node.own());
      }
      /* Children follow their parent in document order, so walking backwards
         sums every subtree before its root. */
      for (let index = nodes.length - 1; index >= 0; index -= 1) {
        const node = nodes[index];
        const tree = { ...node.now.process };
        let descendants = node.hiddenCount;
        if (node.hidden) {
          const extra = node.hidden();
          for (const key of KEYS) tree[key] += extra[key];
        }
        for (const kid of node.kids) {
          for (const key of KEYS) tree[key] += kid.now.tree[key];
          descendants += 1 + kid.descendants;
        }
        node.now.tree = tree;
        node.descendants = descendants;
        for (const scope of ["process", "tree"]) {
          for (const key of KEYS) {
            const series = node.past[scope][key];
            series.push(node.now[scope][key]);
            if (series.length > SLOTS) series.shift();
          }
        }
      }
    }

    function build(node) {
      const row = node.row;
      row.style.setProperty("--depth", node.depth);
      row.innerHTML = `<span class="name"><span class="marker"></span><span class="twist"></span><span class="avatar" style="--av: ${avatarColour(node.name)}">${initials(node.name)}</span><span class="label"></span><span class="count"></span><svg class="spark" viewBox="0 0 52 14" aria-hidden="true"><path/><circle r="1.6"/></svg><span class="pin">${svg("i-pin")}</span></span><span class="num pid">${node.pid}</span><span class="cpu"><span class="meter"><i></i></span><span class="num"></span></span><span class="num rss"></span>`;
      node.cells = {
        marker: row.querySelector(".marker"),
        twist: row.querySelector(".twist"),
        label: row.querySelector(".label"),
        count: row.querySelector(".count"),
        path: row.querySelector(".spark path"),
        dot: row.querySelector(".spark circle"),
        meter: row.querySelector(".meter"),
        cpu: row.querySelector(".cpu .num"),
        rss: row.querySelector(".rss"),
        pid: row.querySelector(".pid"),
      };
      node.cells.label.textContent = node.name;
    }

    function paintRows() {
      const cpuScale = Math.max(0.1, ...nodes.map((node) => Math.max(...node.past.tree.cpu)));
      for (const node of nodes) {
        const { cells, row } = node;
        const cpu = node.now.tree.cpu;
        row.style.setProperty("--heat", clamp(cpu / 100, 0, 1).toFixed(3));
        const hasKids = node.kids.length > 0 || node.hiddenCount > 0;
        const open = node.kids.length > 0 && !node.collapsed;
        const twist = hasKids ? (open ? "i-chevron-down" : "i-chevron-right") : "";
        if (cells.twist.dataset.icon !== twist) {
          cells.twist.dataset.icon = twist;
          cells.twist.innerHTML = twist ? svg(twist) : "";
        }
        cells.count.textContent = node.descendants > 0 ? String(node.descendants) : "";
        if (cells.marker.dataset.change !== (node.change || "")) {
          cells.marker.dataset.change = node.change || "";
          cells.marker.className = `marker ${node.change || ""}`;
          cells.marker.innerHTML = node.change ? svg(node.change === "spawned" ? "i-circle-plus" : "i-circle-minus") : "";
        }
        row.classList.toggle("terminated", node.change === "terminated");
        const recent = node.past.tree.cpu.slice(-20);
        /* A row that has just spawned has one sample; draw it flat. */
        const samples = recent.length > 1 ? recent : [recent[0] || 0, recent[0] || 0];
        const step = 52 / (samples.length - 1);
        const y = (value) => (14 * (1 - value / cpuScale)).toFixed(2);
        cells.path.setAttribute("d", `M${samples.map((value, index) => `${(index * step).toFixed(2)} ${y(value)}`).join("L")}`);
        cells.dot.setAttribute("cx", "52");
        cells.dot.setAttribute("cy", y(samples[samples.length - 1]));
        cells.meter.style.setProperty("--v", clamp(cpu / 100, 0, 1).toFixed(3));
        cells.meter.classList.toggle("warning", cpu >= 50);
        cells.cpu.textContent = percent(cpu);
        cells.cpu.classList.toggle("strong", cpu >= 10);
        cells.cpu.classList.toggle("warn", cpu >= 50);
        cells.rss.textContent = bytes(node.now.tree.mem);
      }
    }

    /* The inspector overview for the selected row. */
    let scope = "tree";
    let selected = null;
    let hover = null;

    function barChart(card, upper, lower, scaleMax, latestIndex) {
      const svgNode = card.querySelector("svg");
      const height = lower ? 56 : 44;
      const lead = SLOTS - upper.length;
      const bars = [];
      const bar = (index, value, below) => {
        const size = (height / (lower ? 2 : 1)) * clamp(value / scaleMax, 0, 1);
        if (size <= 0) return;
        const zero = lower ? height / 2 : height;
        const x = lead + index + 0.15;
        const top = below ? zero : zero - size;
        const classes = [below ? "low" : "", index === latestIndex ? "latest" : ""].join(" ").trim();
        bars.push(`<rect x="${x.toFixed(2)}" y="${top.toFixed(2)}" width="0.7" height="${size.toFixed(2)}"${classes ? ` class="${classes}"` : ""}/>`);
      };
      upper.forEach((value, index) => bar(index, value, false));
      if (lower) lower.forEach((value, index) => bar(index, value, true));
      if (lower) bars.push(`<line x1="0" y1="${height / 2}" x2="${SLOTS}" y2="${height / 2}"/>`);
      svgNode.setAttribute("viewBox", `0 0 ${SLOTS} ${height}`);
      svgNode.innerHTML = bars.join("");
    }

    function chartCard(key, title, detail, diverging) {
      const card = document.createElement("div");
      card.className = `chart-card${diverging ? " diverging" : ""}`;
      card.dataset.chart = key;
      card.innerHTML = `<div class="chart-top"><div><strong>${title}</strong>${detail ? `<small>${detail}</small>` : ""}</div><b></b></div><div class="chart-plot"><div class="chart-scale"><span></span><span></span><span></span></div><div class="chart-bars" style="height: ${diverging ? 56 : 44}px"><svg preserveAspectRatio="none" aria-hidden="true"></svg></div></div>`;
      const bars = card.querySelector(".chart-bars");
      bars.addEventListener("pointermove", (event) => {
        const box = bars.getBoundingClientRect();
        hover = { key, slot: Math.floor(((event.clientX - box.left) / box.width) * SLOTS) };
        paintInspector();
      });
      bars.addEventListener("pointerleave", () => {
        hover = null;
        paintInspector();
      });
      return card;
    }

    const charts = field("charts");
    const CHARTS = [
      chartCard("cpu", "CPU"),
      chartCard("mem", "RSS"),
      chartCard("gpu", "GPU"),
      chartCard("net", "Network history", "Out / In", true),
      chartCard("io", "Storage history", "Read / Write", true),
    ];
    charts.append(...CHARTS);

    function paintInspector() {
      if (!selected) return;
      const node = selected;
      const useTree = scope === "tree";
      const now = node.now[useTree ? "tree" : "process"];
      const past = node.past[useTree ? "tree" : "process"];
      field("name").textContent = node.name;
      field("pid").textContent = node.pid;
      const avatar = field("avatar");
      avatar.textContent = initials(node.name);
      avatar.style.setProperty("--av", avatarColour(node.name));

      const tiles = [
        ["CPU", percent(now.cpu), now.cpu >= 50],
        ["Memory", bytes(now.mem)],
        ["GPU", percent(now.gpu)],
        ["Network", rate(now.in + now.out)],
        ["Storage", rate(now.read + now.write)],
      ];
      if (useTree) tiles.push(["Descendants", String(node.descendants)]);
      field("tiles").innerHTML = tiles
        .map(([label, value, warn]) => `<div class="tile"><small>${label}</small><b${warn ? ' class="warn"' : ""}>${value}</b></div>`)
        .join("");

      const peak = (values, current) => Math.max(0.1, current, ...values);
      const single = [
        ["cpu", past.cpu, now.cpu, percent],
        ["mem", past.mem, now.mem, bytes],
        ["gpu", past.gpu, now.gpu, percent],
      ];
      for (const [key, values, current, format] of single) {
        const card = charts.querySelector(`[data-chart="${key}"]`);
        const max = peak(values, current);
        const hovered = hover && hover.key === key ? hover.slot - (SLOTS - values.length) : -1;
        const index = hovered >= 0 && hovered < values.length ? hovered : values.length - 1;
        card.querySelector("b").textContent = format(current);
        const scale = card.querySelectorAll(".chart-scale span");
        [max, max / 2, 0].forEach((value, position) => (scale[position].textContent = format(value)));
        barChart(card, values, null, max, index);
        tip(card, hovered >= 0 && hovered < values.length ? format(values[hovered]) : null, index, values.length);
      }
      const diverging = [
        ["net", past.out, past.in, now.out, now.in],
        ["io", past.read, past.write, now.read, now.write],
      ];
      for (const [key, upper, lower, upperNow, lowerNow] of diverging) {
        const card = charts.querySelector(`[data-chart="${key}"]`);
        const max = peak([...upper, ...lower], Math.max(upperNow, lowerNow));
        const hovered = hover && hover.key === key ? hover.slot - (SLOTS - upper.length) : -1;
        const index = hovered >= 0 && hovered < upper.length ? hovered : upper.length - 1;
        card.querySelector("b").textContent = `${rate(upperNow)} / ${rate(lowerNow)}`;
        const scale = card.querySelectorAll(".chart-scale span");
        [rate(max), "0", rate(max)].forEach((value, position) => (scale[position].textContent = value));
        barChart(card, upper, lower, max, index);
        tip(card, hovered >= 0 && hovered < upper.length ? `${rate(upper[hovered])} / ${rate(lower[hovered])}` : null, index, upper.length);
      }
    }

    function tip(card, text, index, length) {
      const bars = card.querySelector(".chart-bars");
      let label = bars.querySelector(".chart-tip");
      if (!text) {
        if (label) label.remove();
        return;
      }
      if (!label) {
        label = document.createElement("span");
        label.className = "chart-tip";
        bars.append(label);
      }
      label.textContent = text;
      const centre = ((SLOTS - length + index + 0.5) / SLOTS) * bars.clientWidth;
      const half = label.offsetWidth / 2;
      label.style.left = `${clamp(centre, half, bars.clientWidth - half)}px`;
    }

    function select(node) {
      selected = node;
      for (const other of nodes) other.row.classList.toggle("selected", other === node);
      paintInspector();
    }

    /* Folding hides the subtree's rows; a folded branch inside stays folded. */
    function applyFolding() {
      let hideBelow = Infinity;
      for (const node of nodes) {
        if (node.depth <= hideBelow) hideBelow = Infinity;
        node.row.hidden = node.depth > hideBelow;
        if (!node.row.hidden && node.collapsed && hideBelow === Infinity) hideBelow = node.depth;
      }
    }

    function highlight() {
      const query = search.value.trim().toLowerCase();
      let found = 0;
      for (const node of nodes) {
        const at = query ? node.name.toLowerCase().indexOf(query) : -1;
        const pidHit = query !== "" && node.pid.includes(query);
        node.cells.label.textContent = "";
        if (at >= 0) {
          const mark = document.createElement("mark");
          mark.textContent = node.name.slice(at, at + query.length);
          node.cells.label.append(node.name.slice(0, at), mark, node.name.slice(at + query.length));
        } else {
          node.cells.label.textContent = node.name;
        }
        node.cells.pid.innerHTML = "";
        if (pidHit) {
          const mark = document.createElement("mark");
          mark.textContent = node.pid;
          node.cells.pid.append(mark);
        } else {
          node.cells.pid.textContent = node.pid;
        }
        node.row.classList.toggle("match", at >= 0 || pidHit);
        if (at >= 0 || pidHit) found += 1;
      }
      matches.textContent = query ? String(found) : "";
    }

    /* One short-lived child under the shell: spawned, then terminated. */
    const hostRow = list.querySelector("[data-demo-host]");
    let guest = null;
    let guestAge = 0;
    let guestPid = 2210;

    function guestStep() {
      guestAge += 1;
      const host = nodes.find((node) => node.row === hostRow);
      if (!guest && guestAge >= 6) {
        guestPid += 17;
        const row = document.createElement("button");
        row.type = "button";
        row.className = "tree-row";
        Object.assign(row.dataset, { depth: String(host.depth + 1), name: "cargo build", pid: String(guestPid), cpu: "38", mem: "310", threads: "9", io: "300" });
        hostRow.after(row);
        guest = makeNode(row);
        guest.change = "spawned";
        build(guest);
        nodes.splice(nodes.indexOf(host) + 1, 0, guest);
        link();
        guestAge = 0;
        applyFolding();
        highlight();
      } else if (guest && guestAge === 3) {
        guest.change = null;
      } else if (guest && guestAge === 9) {
        guest.change = "terminated";
        Object.assign(guest.now.process, empty());
      } else if (guest && guestAge >= 11) {
        if (selected === guest) select(host);
        nodes.splice(nodes.indexOf(guest), 1);
        guest.row.remove();
        guest = null;
        guestAge = 0;
        link();
      }
    }

    function tick() {
      guestStep();
      sample();
      paintRows();
      paintInspector();
      count.textContent = String(nodes[0].descendants + 1);
    }

    for (const row of list.querySelectorAll(".tree-row")) nodes.push(makeNode(row));
    link();
    for (const node of nodes) build(node);
    for (let index = 0; index < SLOTS; index += 1) sample();
    paintRows();
    select(nodes.find((node) => node.row.classList.contains("selected")) || nodes[0]);
    count.textContent = String(nodes[0].descendants + 1);

    list.addEventListener("click", (event) => {
      const row = event.target.closest(".tree-row");
      if (!row) return;
      const node = nodes.find((entry) => entry.row === row);
      if (event.target.closest(".twist") && node.kids.length) {
        node.collapsed = !node.collapsed;
        applyFolding();
        paintRows();
        return;
      }
      select(node);
    });
    search.addEventListener("input", highlight);
    lock.addEventListener("click", () => {
      const locked = lock.getAttribute("aria-pressed") !== "true";
      lock.setAttribute("aria-pressed", String(locked));
      lock.querySelector("span").textContent = locked ? "Unlock" : "Lock";
      status.textContent = locked ? "Process tree locked" : liveStatus;
      state.classList.toggle("live", !locked);
      state.classList.toggle("neutral", locked);
    });
    for (const button of figure.querySelectorAll("[data-demo-scope]")) {
      button.addEventListener("click", () => {
        scope = button.dataset.demoScope;
        for (const other of figure.querySelectorAll("[data-demo-scope]")) other.setAttribute("aria-pressed", String(other === button));
        paintInspector();
      });
    }

    /* The signature at the foot of the sidebar opens About, as in the app. */
    const about = figure.querySelector("[data-demo-about]");
    const aboutOpen = figure.querySelector("[data-demo-about-open]");
    const aboutClose = figure.querySelector("[data-demo-about-close]");
    const closeAbout = () => {
      about.hidden = true;
      aboutOpen.focus();
    };
    aboutOpen.addEventListener("click", () => {
      about.hidden = false;
      aboutClose.focus();
    });
    aboutClose.addEventListener("click", closeAbout);
    about.addEventListener("click", (event) => {
      if (event.target === about) closeAbout();
    });
    about.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeAbout();
      if (event.key === "Tab") {
        event.preventDefault();
        aboutClose.focus();
      }
    });

    /* The sketch starts in the page's appearance; the switch overrides it. */
    const themeButtons = figure.querySelectorAll("[data-demo-theme]");
    const showTheme = (theme) => {
      for (const button of themeButtons) button.setAttribute("aria-pressed", String(button.dataset.demoTheme === theme));
    };
    const pageScheme = matchMedia("(prefers-color-scheme: dark)");
    showTheme(pageScheme.matches ? "dark" : "light");
    pageScheme.addEventListener("change", () => {
      if (!app.dataset.theme) showTheme(pageScheme.matches ? "dark" : "light");
    });
    for (const button of themeButtons) {
      button.addEventListener("click", () => {
        app.dataset.theme = button.dataset.demoTheme;
        showTheme(button.dataset.demoTheme);
      });
    }

    let onScreen = false;
    new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
    }).observe(figure);
    setInterval(() => {
      if (onScreen && !document.hidden) tick();
    }, 1000);
  }

  function detectPlatform() {
    const hint = `${(navigator.userAgentData && navigator.userAgentData.platform) || ""} ${navigator.platform || ""} ${navigator.userAgent}`;
    if (/android|iphone|ipad|ipod/i.test(hint)) return null;
    if (/mac/i.test(hint)) return "macos";
    if (/win/i.test(hint)) return "windows";
    if (/linux|x11/i.test(hint)) return "linux";
    return null;
  }

  function markPlatform() {
    const platform = detectPlatform();
    if (!platform) return;
    for (const card of document.querySelectorAll(`.os-card[data-platform="${platform}"]`)) {
      card.classList.add("is-yours");
      const badge = card.querySelector("[data-yours]");
      if (badge) badge.hidden = false;
    }
  }

  function sizeLabel(bytes) {
    let size = Number(bytes) || 0;
    const units = ["B", "KB", "MB", "GB"];
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return unit ? `${size.toFixed(1)} ${units[unit]}` : `${size} B`;
  }

  /* Point the landing page's download cards at the newest published build.
     Until the data arrives, or if it cannot be read, they link to the
     downloads page. */
  async function hydrateDownloads(section) {
    let data;
    try {
      const response = await fetch("_data/releases.json", { cache: "no-cache" });
      if (!response.ok) return;
      data = await response.json();
    } catch {
      return;
    }
    const release = data.latest || (data.beta && data.beta.latest);
    if (!release || !Array.isArray(release.artifacts)) return;
    const href = (path) => String(path || "").replace(/^\//, "");

    for (const card of section.querySelectorAll(".os-card")) {
      const files = release.artifacts.filter((artifact) => artifact.platform === card.dataset.platform);
      for (const link of card.querySelectorAll("[data-format]")) {
        const artifact = files.find((entry) => entry.format === link.dataset.format);
        if (!artifact || !artifact.downloadPath) continue;
        link.href = href(artifact.downloadPath);
        link.querySelector("[data-size]").textContent = sizeLabel(artifact.sizeBytes);
      }
      const first = files[0];
      const requires = card.querySelector('[data-release="requires"]');
      if (first && requires) {
        const system = first.minimumSystem && first.minimumSystem !== "Linux" ? first.minimumSystem : "";
        requires.textContent = [first.architectures, system].filter(Boolean).join(" · ");
      }
    }

    const set = (name, text) => {
      for (const node of document.querySelectorAll(`[data-release="${name}"]`)) node.textContent = text;
    };
    set("version", release.version);
    set("channel", release.channel === "beta" ? "Beta" : "Stable");
    set("detail", `${release.version} · build ${release.build} · ${release.released}`);
    set("about", `Version ${release.version} · build ${release.build}`);
    const notes = section.querySelector('[data-release="notes"]');
    if (release.notesPath) notes.href = href(release.notesPath);
    section.querySelector('[data-release="line"]').hidden = false;
  }

  function copyButtons() {
    document.addEventListener("click", async (event) => {
      const button = event.target.closest("[data-copy]");
      if (!button) return;
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
      } catch {
        return;
      }
      const label = button.textContent;
      button.textContent = "Copied";
      button.classList.add("is-done");
      setTimeout(() => {
        button.textContent = label;
        button.classList.remove("is-done");
      }, 1500);
    });
  }

  function reveals() {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("is-in");
          observer.unobserve(entry.target);
        }
      },
      { rootMargin: "0px 0px -8% 0px" },
    );
    for (const node of document.querySelectorAll(".reveal")) {
      const siblings = [...node.parentElement.children].filter((child) => child.classList.contains("reveal"));
      node.style.setProperty("--i", String(Math.min(siblings.indexOf(node), 6)));
      observer.observe(node);
    }
  }

  /* The feature trunk fills as the list scrolls into view. */
  function featureTrunk(list) {
    let queued = false;
    const update = () => {
      queued = false;
      const box = list.getBoundingClientRect();
      list.style.setProperty("--grow", clamp((innerHeight * 0.7 - box.top) / box.height, 0, 1).toFixed(3));
    };
    addEventListener(
      "scroll",
      () => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(update);
      },
      { passive: true },
    );
    addEventListener("resize", update);
    update();
  }

  const canvas = document.querySelector("[data-hero-tree]");
  if (canvas) heroTree(canvas);
  const figure = document.querySelector("[data-demo]");
  if (figure) windowSketch(figure);
  const downloads = document.querySelector("[data-downloads]");
  if (downloads) hydrateDownloads(downloads);
  const trunk = document.querySelector("[data-ftree]");
  if (trunk) featureTrunk(trunk);
  markPlatform();
  copyButtons();
  reveals();
})();
