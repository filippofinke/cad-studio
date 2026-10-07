const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const icons = {
  think: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M6 13.5h4M6.5 11.5h3M8 2a4.2 4.2 0 00-2.4 7.6c.4.3.6.7.6 1.2V11h3.6v-.2c0-.5.2-.9.6-1.2A4.2 4.2 0 008 2z" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  terminal: '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M4.5 6.5l2 1.5-2 1.5M8 10h3" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  file: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M9.5 1.5H4A1.5 1.5 0 002.5 3v10A1.5 1.5 0 004 14.5h8a1.5 1.5 0 001.5-1.5V5.5l-4-4zM9.5 1.5v4h4M8 8v4M6 10h4" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  read: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M9.5 1.5H4A1.5 1.5 0 002.5 3v10A1.5 1.5 0 004 14.5h3M9.5 1.5v4h4M9.5 1.5l4 4v2" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round"/><circle cx="11" cy="11" r="2.2" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M12.6 12.6l1.9 1.9" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>',
  ok: '<svg class="ok" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5l3 3 7-7" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  version: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><path d="M2.8 8a5.2 5.2 0 109-3.6M11.8 1.6v2.8H9M8 5v3l2 1.4" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
};

const prompt = "An under-desk headphone hook that screws to the desk with two M4 screws in countersunk holes. 25 mm wide.";

const modelLines = [
  '"""Under-desk headphone hook, screwed to the desk underside with two M4 countersunk screws."""',
  "from build123d import (",
  "    Polygon, Pos, Rot, Vector, extrude, fillet, Cylinder, Cone, Align,",
  "    Mesher, export_stl, export_step,",
  ")",
  "WIDTH = 25.0            # hook width (Y), mm",
  "THICKNESS = 6.0         # thickness of plate, stem, arm and lip, mm",
  "PLATE_LEN = 45.0        # length of the screw plate behind the stem (-X), mm",
  "HOOK_GAP = 35.0         # clear height between arm top and desk underside, mm",
  "ARM_LEN = 55.0          # length of the hook arm measured from the stem back face (+X), mm",
  "LIP_H = 10.0            # height of the retaining lip above the arm top, mm",
  "INNER_R = 8.0           # fillet radius of the inner stem/arm corner (headband seat), mm",
  "HOLE_D = 4.5            # M4 clearance hole diameter, mm",
  "CSK_D = 8.6             # countersink diameter at the bottom face (M4 head 8.4 + clearance), mm",
  "def build():",
  "    profile = Polygon(*outline(), align=None)",
  "    hook = extrude(profile, amount=WIDTH / 2, both=True)",
  "    return fillet(hook.edges().filter_by(Axis.Y), INNER_R)"
];

const reply = "I made a 25 mm wide J-shaped headphone hook. A 45 mm plate fixes it under the desk with two M4 countersunk screws inserted from below, the gap to the desk is 35 mm, and a 10 mm lip at the front stops the headband sliding off.";

function sessionReplay() {
  const session = document.getElementById("session");
  if (!session) return;
  const typed = session.querySelector("[data-typed]");
  const promptBox = session.querySelector("[data-prompt]");
  const feed = session.querySelector("[data-feed]");
  const statusText = session.querySelector("[data-status-text]");
  const timer = session.querySelector("[data-timer]");
  const replayButton = session.querySelector("[data-replay]");
  const realSeconds = 164;
  const speed = 15;
  let run = 0;
  let clockStart = 0;
  let clockFrame = 0;

  const wait = (ms, id) => new Promise((resolve, reject) => {
    setTimeout(() => (id === run ? resolve() : reject(new Error("cancelled"))), reducedMotion ? 0 : ms);
  });

  const setStatus = (text) => {
    statusText.textContent = text;
  };

  const tickClock = () => {
    const elapsed = Math.min((performance.now() - clockStart) / 1000 * speed, realSeconds);
    const minutes = Math.floor(elapsed / 60);
    const seconds = Math.floor(elapsed % 60).toString().padStart(2, "0");
    timer.textContent = `${minutes}:${seconds}`;
    clockFrame = requestAnimationFrame(tickClock);
  };

  const add = (html, className) => {
    const element = document.createElement("div");
    element.className = className;
    element.innerHTML = html;
    feed.appendChild(element);
    feed.scrollTop = feed.scrollHeight;
    return element;
  };

  const toolRow = (icon, title) => add(
    `<div class="row-tool-head">${icons[icon]}<span>${title}</span><i class="spinner" aria-hidden="true"></i></div>`,
    "row-tool"
  );

  const finishTool = (row, title) => {
    const head = row.querySelector(".row-tool-head");
    if (title) head.querySelector("span").textContent = title;
    head.querySelector(".spinner").outerHTML = icons.ok;
    row.querySelector(".row-preview")?.remove();
  };

  const reset = () => {
    cancelAnimationFrame(clockFrame);
    session.classList.remove("is-working", "is-done", "is-drawn");
    promptBox.classList.remove("is-sent");
    typed.textContent = "";
    feed.innerHTML = "";
    timer.textContent = "0:00";
    setStatus("Ready");
  };

  const play = async () => {
    const id = ++run;
    reset();
    try {
      await wait(500, id);
      for (let index = 1; index <= prompt.length; index++) {
        typed.textContent = prompt.slice(0, index);
        if (!reducedMotion) await wait(index % 9 === 0 ? 60 : 22, id);
      }
      await wait(350, id);
      promptBox.classList.add("is-sent");
      session.classList.add("is-working", "is-drawn");
      clockStart = performance.now();
      if (!reducedMotion) tickClock();
      setStatus("Claude is thinking…");

      const think = add(`${icons.think}<span>Thinking · about 0 tokens</span>`, "row-think");
      const thinkLabel = think.querySelector("span");
      for (let tokens = 0; tokens <= 1250; tokens += 50) {
        thinkLabel.textContent = `Thinking · about ${tokens.toLocaleString("en-US")} tokens`;
        await wait(45, id);
      }
      thinkLabel.textContent = "Thought for 18 s";

      setStatus("Claude is working… · Creates model.py");
      const write = toolRow("file", "Creates model.py · 1 line");
      const preview = document.createElement("div");
      preview.className = "row-preview";
      write.appendChild(preview);
      const total = 303;
      for (let step = 1; step <= 36; step++) {
        const lines = Math.round(total * step / 36);
        write.querySelector("span").textContent = `Creates model.py · ${lines} lines`;
        const index = Math.min(modelLines.length - 1, Math.floor(step / 2));
        preview.textContent = modelLines.slice(Math.max(0, index - 3), index + 1).join("\n");
        await wait(70, id);
      }
      finishTool(write, "Creates model.py");

      setStatus("Claude is working… · Runs python model.py");
      const runRow = toolRow("terminal", "Runs python model.py");
      await wait(1100, id);
      finishTool(runRow);

      setStatus("Claude is working… · Reads output/schematic.png");
      const readRow = toolRow("read", "Reads output/schematic.png");
      await wait(700, id);
      finishTool(readRow);

      session.classList.remove("is-working");
      session.classList.add("is-done");
      cancelAnimationFrame(clockFrame);
      timer.textContent = "2:44";
      setStatus("Model generated");

      const replyRow = add("", "row-reply");
      const words = reply.split(" ");
      for (let index = 1; index <= words.length; index++) {
        replyRow.textContent = words.slice(0, index).join(" ");
        feed.scrollTop = feed.scrollHeight;
        await wait(28, id);
      }
      add(`${icons.version}<span>Version 1</span>`, "row-version");
    } catch {
      return;
    }
  };

  replayButton.addEventListener("click", play);
  const observer = new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) {
      observer.disconnect();
      play();
    }
  }, { threshold: 0.25 });
  observer.observe(session);
}

function parameterDrawing() {
  const svg = document.querySelector("[data-profile]");
  const code = document.querySelector("[data-code]");
  if (!svg || !code) return;
  const total = document.querySelector("[data-total]");
  const inputs = [...document.querySelectorAll("[data-param]")];
  const params = { WIDTH: 25, THICKNESS: 6, PLATE_LEN: 45, HOOK_GAP: 35, ARM_LEN: 55, LIP_H: 10 };
  const comments = {
    WIDTH: "hook width (Y), mm",
    THICKNESS: "thickness of plate, stem, arm and lip, mm",
    PLATE_LEN: "length of the screw plate behind the stem (-X), mm",
    HOOK_GAP: "clear height between arm top and desk underside, mm",
    ARM_LEN: "length of the hook arm from the stem back face (+X), mm",
    LIP_H: "height of the retaining lip above the arm top, mm"
  };
  const order = ["WIDTH", "THICKNESS", "PLATE_LEN", "HOOK_GAP", "ARM_LEN", "LIP_H"];
  let lastChanged = null;

  const format = (value) => Number(value).toFixed(1);

  const renderCode = () => {
    code.innerHTML = order.map((name) => {
      const left = `${name} = `;
      const value = format(params[name]);
      const pad = " ".repeat(Math.max(1, 24 - left.length - value.length));
      const flash = name === lastChanged ? " is-flash" : "";
      return `<span>${left}<span class="n${flash}" data-n="${name}">${value}</span>${pad}<span class="c"># ${comments[name]}</span></span>`;
    }).join("\n");
    if (lastChanged) {
      requestAnimationFrame(() => code.querySelector(`[data-n="${lastChanged}"]`)?.classList.remove("is-flash"));
    }
  };

  const rounded = (points, radii) => {
    const count = points.length;
    let path = "";
    for (let index = 0; index < count; index++) {
      const previous = points[(index - 1 + count) % count];
      const current = points[index];
      const next = points[(index + 1) % count];
      const radius = radii[index] || 0;
      const toPrevious = [previous[0] - current[0], previous[1] - current[1]];
      const toNext = [next[0] - current[0], next[1] - current[1]];
      const lengthPrevious = Math.hypot(...toPrevious);
      const lengthNext = Math.hypot(...toNext);
      const r = Math.min(radius, lengthPrevious / 2, lengthNext / 2);
      const start = [current[0] + toPrevious[0] / lengthPrevious * r, current[1] + toPrevious[1] / lengthPrevious * r];
      const end = [current[0] + toNext[0] / lengthNext * r, current[1] + toNext[1] / lengthNext * r];
      path += `${index === 0 ? "M" : "L"}${start[0].toFixed(2)} ${start[1].toFixed(2)} Q${current[0].toFixed(2)} ${current[1].toFixed(2)} ${end[0].toFixed(2)} ${end[1].toFixed(2)} `;
    }
    return `${path}Z`;
  };

  const arrow = (x, y, angle) => {
    const length = 2.2;
    const spread = 0.42;
    const a = [x + Math.cos(angle + spread) * length, y + Math.sin(angle + spread) * length];
    const b = [x + Math.cos(angle - spread) * length, y + Math.sin(angle - spread) * length];
    return `<path class="arrow" d="M${x} ${y} L${a[0]} ${a[1]} L${b[0]} ${b[1]} Z"/>`;
  };

  const horizontal = (x1, x2, y, label, live) => {
    const mid = (x1 + x2) / 2;
    return `<line class="dimline" x1="${x1}" y1="${y}" x2="${x2}" y2="${y}"/>${arrow(x1, y, 0)}${arrow(x2, y, Math.PI)}<text x="${mid}" y="${y - 1.4}" text-anchor="middle" class="${live ? "is-live" : ""}">${label}</text>`;
  };

  const vertical = (x, y1, y2, label, live) => {
    const mid = (y1 + y2) / 2;
    return `<line class="dimline" x1="${x}" y1="${y1}" x2="${x}" y2="${y2}"/>${arrow(x, y1, Math.PI / 2)}${arrow(x, y2, -Math.PI / 2)}<text x="${x + 1.6}" y="${mid + 1.5}" class="${live ? "is-live" : ""}">${label}</text>`;
  };

  const ext = (x1, y1, x2, y2) => `<line class="ext" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;

  const render = () => {
    const t = params.THICKNESS;
    const p = params.PLATE_LEN;
    const gap = params.HOOK_GAP;
    const arm = params.ARM_LEN;
    const lip = params.LIP_H;
    const height = 2 * t + gap;
    const ox = 62;
    const oy = 14;
    const X = (x) => ox + x;
    const Y = (z) => oy - z;
    const points = [
      [-p, 0], [t, 0], [t, -(t + gap)], [arm - t, -(t + gap)], [arm - t, -(t + gap) + lip],
      [arm, -(t + gap) + lip], [arm, -height], [0, -height], [0, -t], [-p, -t]
    ].map(([x, z]) => [X(x), Y(z)]);
    const radii = [1, 0, 8, 1.2, 2.5, 2.5, 3, 8 + t, 6, 1];
    const holes = [-p * 0.28, -p * 0.72].map((x) => {
      const hx = X(x);
      return `<line class="hidden" x1="${hx - 2.25}" y1="${Y(0)}" x2="${hx - 2.25}" y2="${Y(-t) - 2}"/><line class="hidden" x1="${hx + 2.25}" y1="${Y(0)}" x2="${hx + 2.25}" y2="${Y(-t) - 2}"/><path class="hidden" d="M${hx - 4.3} ${Y(-t)} L${hx - 2.25} ${Y(-t) - 2} M${hx + 4.3} ${Y(-t)} L${hx + 2.25} ${Y(-t) - 2}"/><line class="axis" x1="${hx}" y1="${Y(0) - 3}" x2="${hx}" y2="${Y(-t) + 3}"/>`;
    }).join("");
    const desk = `<rect class="desk" x="${X(-p - 8)}" y="${Y(0) - 5}" width="${p + 8 + 98}" height="5"/>`;
    const below = Y(-height);
    const gapX = X(t + Math.min(arm - 2 * t, 26) * 0.55 + 4);
    const dims = [
      horizontal(X(0), X(arm), below + 9, `ARM_LEN ${format(arm)}`, lastChanged === "ARM_LEN"),
      ext(X(0), below + 1, X(0), below + 11),
      ext(X(arm), below + 1, X(arm), below + 11),
      horizontal(X(-p), X(0), Y(0) - 10, `PLATE_LEN ${format(p)}`, false),
      ext(X(-p), Y(0) - 1, X(-p), Y(0) - 12),
      ext(X(0), Y(0) - 6, X(0), Y(0) - 12),
      vertical(gapX, Y(-t), Y(-(t + gap)), `HOOK_GAP ${format(gap)}`, lastChanged === "HOOK_GAP"),
      vertical(X(arm) + 8, Y(-(t + gap)), Y(-(t + gap) + lip), `LIP_H ${format(lip)}`, lastChanged === "LIP_H"),
      ext(X(arm) + 1, Y(-(t + gap) + lip), X(arm) + 10, Y(-(t + gap) + lip)),
      ext(X(arm - t) + 1, Y(-(t + gap)), X(arm) + 10, Y(-(t + gap))),
      vertical(X(-p) - 7, Y(0), Y(-height), `${format(height)}`, lastChanged === "HOOK_GAP" || lastChanged === "THICKNESS"),
      ext(X(-p) - 1, Y(-t), X(-p) - 9, Y(-t)),
      ext(X(0) - 1, Y(-height), X(-p) - 9, Y(-height))
    ].join("");
    svg.innerHTML = `<defs><pattern id="hatch" width="2.2" height="2.2" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="2.2" stroke="#9aa0aa" stroke-width="0.35"/></pattern></defs>${desk}<path class="body" d="${rounded(points, radii)}"/>${holes}${dims}`;
    const bottom = below + 16;
    svg.setAttribute("viewBox", `0 -2 ${X(arm) + 40} ${Math.max(bottom, 100) + 2}`);
    total.textContent = `Overall height ${format(height)} mm`;
  };

  const syncFill = (input) => {
    const min = Number(input.min);
    const max = Number(input.max);
    input.style.setProperty("--fill", `${((Number(input.value) - min) / (max - min)) * 100}%`);
  };

  inputs.forEach((input) => {
    syncFill(input);
    input.addEventListener("input", () => {
      params[input.dataset.param] = Number(input.value);
      lastChanged = input.dataset.param;
      document.querySelector(`[data-out="${input.dataset.param}"]`).textContent = input.value;
      syncFill(input);
      render();
      renderCode();
    });
  });

  render();
  renderCode();
}

function sheetStack() {
  const stack = document.querySelector("[data-sheets]");
  if (!stack) return;
  const sheets = [...stack.querySelectorAll("img")];
  const buttons = [...document.querySelectorAll("[data-sheet]")];
  let current = 0;

  const show = (index) => {
    current = index;
    sheets.forEach((sheet, sheetIndex) => {
      sheet.dataset.depth = String((sheetIndex - index + sheets.length) % sheets.length);
    });
    buttons.forEach((button) => button.setAttribute("aria-pressed", String(Number(button.dataset.sheet) === index)));
  };

  buttons.forEach((button) => button.addEventListener("click", () => show(Number(button.dataset.sheet))));
  stack.addEventListener("click", () => show((current + 1) % sheets.length));
  show(0);
}

function partViews() {
  const stage = document.querySelector("[data-views]");
  if (!stage) return;
  const images = [...stage.querySelectorAll("img")];
  const tabs = [...document.querySelectorAll("[data-view]")];

  const select = (index) => {
    images.forEach((image, imageIndex) => image.classList.toggle("is-on", imageIndex === index));
    tabs.forEach((tab) => tab.setAttribute("aria-selected", String(Number(tab.dataset.view) === index)));
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => select(Number(tab.dataset.view)));
    tab.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      const next = (Number(tab.dataset.view) + (event.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length;
      select(next);
      tabs[next].focus();
    });
  });
}

function copyButtons() {
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const text = button.parentElement.querySelector("code").textContent;
      try {
        await navigator.clipboard.writeText(text);
        button.classList.add("is-copied");
        setTimeout(() => button.classList.remove("is-copied"), 1400);
      } catch {
        button.classList.remove("is-copied");
      }
    });
  });
}

function chrome() {
  const nav = document.querySelector(".nav");
  const update = () => nav.classList.toggle("is-scrolled", window.scrollY > 8);
  update();
  window.addEventListener("scroll", update, { passive: true });

  if (reducedMotion) return;
  const targets = document.querySelectorAll(".split-head, .params-stage, .drawings-grid, .motion-stage, .views-grid, .shot, .facts, .steps, .close");
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-in");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
  targets.forEach((target) => {
    target.classList.add("reveal");
    observer.observe(target);
  });
}

sessionReplay();
parameterDrawing();
sheetStack();
partViews();
copyButtons();
chrome();
