import * as THREE from "three";
import { ThreeMFLoader } from "./vendor/three/addons/loaders/3MFLoader.js";
import { RoomEnvironment } from "./vendor/three/addons/environments/RoomEnvironment.js";
import { toCreasedNormals } from "./vendor/three/addons/utils/BufferGeometryUtils.js";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const ease = (t) => 1 - Math.pow(1 - clamp(t), 3);
const smooth = (t) => {
  const x = clamp(t);
  return x * x * (3 - 2 * x);
};

const sectionProgress = (element) => {
  const rect = element.getBoundingClientRect();
  const travel = rect.height - window.innerHeight;
  return travel > 0 ? clamp(-rect.top / travel) : clamp(1 - rect.bottom / (window.innerHeight + rect.height));
};

const partColors = {
  housing: "#a9abb1",
  lid: "#bfc1c7",
  plunger: "#9a9ca3",
  follower: "#d62828",
  spring: "#2a2a2d"
};

const partLabels = {
  housing: "Housing",
  lid: "Lid",
  plunger: "Plunger with cam groove",
  follower: "Follower pin",
  spring: "Serpentine spring"
};

const groupName = (name) => {
  const base = name.replace(/[_\-\s]?\d+$/, "");
  return base || name;
};

function webglAvailable() {
  try {
    const canvas = document.createElement("canvas");
    return Boolean(window.WebGL2RenderingContext && canvas.getContext("webgl2"));
  } catch {
    return false;
  }
}

class Stage {
  constructor(canvas, { url, fov = 26 }) {
    this.canvas = canvas;
    this.visible = false;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.camera = new THREE.PerspectiveCamera(fov, 1, 1, 5000);
    const key = new THREE.DirectionalLight(0xffffff, 1.6);
    key.position.set(-1.2, 2, 1.6);
    const rim = new THREE.DirectionalLight(0xbcd4ff, 2.2);
    rim.position.set(1.8, 0.6, -2);
    this.scene.add(key, rim, new THREE.AmbientLight(0xffffff, 0.15));
    this.pivot = new THREE.Group();
    this.scene.add(this.pivot);
    this.ready = new Promise((resolve, reject) => {
      new ThreeMFLoader().load(url, (object) => {
        this.model = object;
        this.prepare(object);
        resolve(this);
      }, undefined, reject);
    });
    new ResizeObserver(() => this.resize()).observe(canvas);
    new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
    }, { rootMargin: "200px" }).observe(canvas);
  }

  prepare(object) {
    object.rotation.x = -Math.PI / 2;
    object.updateMatrixWorld(true);
    object.traverse((child) => {
      if (!child.isMesh) return;
      const geometry = toCreasedNormals(child.geometry, THREE.MathUtils.degToRad(32));
      child.geometry.dispose();
      child.geometry = geometry;
      const name = groupName(child.name || child.parent?.name || "");
      child.userData.part = name;
      const source = child.material?.color;
      const own = source && source.getHex() !== 0xffffff ? source.clone().convertSRGBToLinear() : null;
      const vertexColors = Boolean(geometry.attributes.color);
      child.material = new THREE.MeshPhysicalMaterial({
        color: vertexColors ? "#ffffff" : partColors[name] || own || "#e4e6ea",
        vertexColors,
        roughness: name === "spring" ? 0.55 : 0.42,
        metalness: 0.02,
        clearcoat: 0.35,
        clearcoatRoughness: 0.5,
        sheen: 0.1,
        sheenColor: new THREE.Color("#ffffff")
      });
    });
    const box = new THREE.Box3().setFromObject(object);
    const center = box.getCenter(new THREE.Vector3());
    object.position.sub(center);
    this.radius = box.getSize(new THREE.Vector3()).length() / 2;
    this.pivot.add(object);
  }

  resize() {
    const width = this.canvas.clientWidth;
    const height = this.canvas.clientHeight;
    if (!width || !height) return;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  frame(distanceScale = 1, elevation = 0.32) {
    if (!this.radius) return;
    const fit = this.radius / Math.sin(THREE.MathUtils.degToRad(this.camera.fov / 2));
    const aspectFit = this.camera.aspect < 1.2 ? fit * 1.2 / Math.max(this.camera.aspect, 0.4) : fit;
    const distance = aspectFit * distanceScale;
    this.camera.position.set(0, Math.sin(elevation) * distance, Math.cos(elevation) * distance);
    this.camera.lookAt(0, 0, 0);
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }
}

function motionPlayer(study) {
  const frames = [...study.frames].sort((a, b) => a.t - b.t);
  const duration = frames.at(-1)?.t || 0;
  const quaternion = (pose) => {
    const r = pose?.rotate;
    return r && r.length === 4 ? new THREE.Quaternion(r[0], r[1], r[2], r[3]).normalize() : new THREE.Quaternion();
  };
  const vector = (pose) => {
    const t = pose?.translate;
    return t && t.length === 3 ? new THREE.Vector3(t[0], t[1], t[2]) : new THREE.Vector3();
  };
  return {
    duration,
    names: [...new Set(frames.flatMap((frame) => Object.keys(frame.parts || {})))],
    pose(name, time) {
      const t = duration > 0 ? ((time % duration) + duration) % duration : 0;
      const upper = Math.max(1, frames.findIndex((frame) => frame.t >= t));
      const next = frames[Math.min(upper, frames.length - 1)];
      const previous = frames[upper - 1] || next;
      const span = next.t - previous.t;
      const f = span > 0 ? clamp((t - previous.t) / span) : 0;
      const a = previous.parts?.[name] || next.parts?.[name];
      const b = next.parts?.[name] || a;
      const q = quaternion(a).slerp(quaternion(b), f);
      const v = vector(a).lerp(vector(b), f);
      return new THREE.Matrix4().compose(v, q, new THREE.Vector3(1, 1, 1));
    }
  };
}

function setupHeroStage(canvas) {
  const stage = new Stage(canvas, { url: canvas.dataset.model });
  const hero = canvas.closest(".hero");
  const animation = canvas.dataset.animation
    ? fetch(canvas.dataset.animation).then((response) => (response.ok ? response.json() : null)).catch(() => null)
    : Promise.resolve(null);
  let pointerX = 0;
  let pointerY = 0;
  let smoothX = 0;
  let smoothY = 0;
  window.addEventListener("pointermove", (event) => {
    pointerX = event.clientX / window.innerWidth - 0.5;
    pointerY = event.clientY / window.innerHeight - 0.5;
  }, { passive: true });
  return Promise.all([stage.ready, animation]).then(([, study]) => {
    const player = study?.frames?.length > 1 ? motionPlayer(study) : null;
    const meshes = [];
    const height = new THREE.Box3().setFromObject(stage.model).getSize(new THREE.Vector3()).y;
    const lifted = canvas.dataset.lift || "";
    const lift = new THREE.Matrix4();
    stage.model.traverse((child) => {
      if (!child.isMesh) return;
      child.matrixAutoUpdate = false;
      child.updateMatrix();
      meshes.push({ mesh: child, base: child.matrix.clone(), name: child.name || child.parent?.name || "" });
    });
    return (time) => {
      if (!stage.visible) return;
      const scroll = clamp(-hero.getBoundingClientRect().top / hero.offsetHeight);
      smoothX += (pointerX - smoothX) * 0.05;
      smoothY += (pointerY - smoothY) * 0.05;
      const intro = reducedMotion ? 1 : ease(time / 2200);
      const seconds = reducedMotion ? 0 : time / 1000;
      const raise = height * (0.25 + 0.75 * intro) * (1 + scroll * 1.2);
      for (const { mesh, base, name } of meshes) {
        const pose = player ? player.pose(name, seconds) : new THREE.Matrix4();
        lift.makeTranslation(0, 0, name === lifted ? raise : 0);
        mesh.matrix.multiplyMatrices(lift, pose).multiply(base);
      }
      stage.pivot.rotation.y = -0.5 + intro * 0.35 + (reducedMotion ? 0 : time * 0.00005) + scroll * 0.9 + smoothX * 0.45;
      stage.pivot.rotation.x = smoothY * 0.1;
      stage.frame(0.9 - scroll * 0.12 + (1 - intro) * 0.4, 0.42 + scroll * 0.25);
      stage.render();
    };
  });
}

function explodedOffsets(model) {
  const groups = new Map();
  model.updateMatrixWorld(true);
  model.traverse((child) => {
    if (!child.isMesh) return;
    const name = child.userData.part;
    const box = new THREE.Box3().setFromBufferAttribute(child.geometry.attributes.position);
    box.applyMatrix4(child.matrix);
    if (!groups.has(name)) groups.set(name, { box: box.clone(), meshes: [] });
    groups.get(name).box.union(box);
    groups.get(name).meshes.push(child);
  });
  const entries = [...groups.entries()];
  const volume = (box) => {
    const size = box.getSize(new THREE.Vector3());
    return size.x * size.y * size.z;
  };
  const largest = Math.max(...entries.map(([, group]) => volume(group.box)));
  const [anchorName, anchor] = entries
    .filter(([, group]) => volume(group.box) >= largest * 0.6)
    .reduce((best, entry) => (entry[1].box.min.z < best[1].box.min.z ? entry : best));
  const anchorCenter = anchor.box.getCenter(new THREE.Vector3());
  const overall = entries.reduce((box, [, group]) => box.union(group.box), anchor.box.clone());
  const gap = Math.max(overall.getSize(new THREE.Vector3()).length() * 0.06, 2);
  const placed = [anchor.box.clone()];
  const others = entries
    .filter(([name]) => name !== anchorName)
    .sort((a, b) => a[1].box.getCenter(new THREE.Vector3()).distanceTo(anchorCenter) - b[1].box.getCenter(new THREE.Vector3()).distanceTo(anchorCenter));
  const result = new Map([[anchorName, { meshes: anchor.meshes, offset: new THREE.Vector3(), box: anchor.box }]]);
  for (const [name, group] of others) {
    const delta = group.box.getCenter(new THREE.Vector3()).sub(anchorCenter);
    const magnitude = new THREE.Vector3(Math.abs(delta.x), Math.abs(delta.y), Math.abs(delta.z));
    let direction = new THREE.Vector3(0, 0, 1);
    if (Math.max(magnitude.x, magnitude.y, magnitude.z) > 0.01) {
      if (magnitude.z >= magnitude.x && magnitude.z >= magnitude.y) direction.set(0, 0, Math.sign(delta.z));
      else if (magnitude.x >= magnitude.y) direction.set(Math.sign(delta.x), 0, 0);
      else direction.set(0, Math.sign(delta.y), 0);
    }
    const step = Math.max(group.box.getSize(new THREE.Vector3()).length() * 0.05, 0.5);
    let travel = 0;
    const moved = group.box.clone();
    const overlaps = () => placed.some((other) => moved.clone().expandByScalar(gap * 0.25).intersectsBox(other));
    while (travel < 10000 && overlaps()) {
      travel += step;
      moved.copy(group.box).translate(direction.clone().multiplyScalar(travel));
    }
    const offset = direction.clone().multiplyScalar(travel + gap);
    placed.push(group.box.clone().translate(offset));
    result.set(name, { meshes: group.meshes, offset, box: group.box });
  }
  return result;
}

function setupLatchStage(canvas) {
  const stage = new Stage(canvas, { url: "models/latch.3mf", fov: 24 });
  const section = canvas.closest(".parts");
  const lines = [...section.querySelectorAll("[data-line]")];
  const labelList = section.querySelector("[data-part-labels]");
  return stage.ready.then(() => {
    const parts = explodedOffsets(stage.model);
    const labels = new Map();
    for (const [name] of parts) {
      const item = document.createElement("li");
      item.textContent = partLabels[name] || name;
      labelList.appendChild(item);
      labels.set(name, item);
    }
    const origins = new Map();
    for (const [, part] of parts) {
      for (const mesh of part.meshes) origins.set(mesh, mesh.position.clone());
    }
    const projected = new THREE.Vector3();
    return () => {
      if (!stage.visible) return;
      const progress = sectionProgress(section);
      const amount = smooth((progress - 0.22) / 0.42);
      const index = progress < 0.22 ? 0 : progress < 0.66 ? 1 : 2;
      lines.forEach((line, lineIndex) => line.classList.toggle("is-on", lineIndex === index));
      for (const [, part] of parts) {
        for (const mesh of part.meshes) {
          mesh.position.copy(origins.get(mesh)).addScaledVector(part.offset, amount);
        }
      }
      stage.pivot.rotation.y = -0.65 + progress * 0.9;
      stage.frame(1.15 + amount * 0.38, 0.42 - progress * 0.12);
      stage.render();
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const canvasRect = canvas.getBoundingClientRect();
      const listRect = labelList.getBoundingClientRect();
      for (const [name, part] of parts) {
        const label = labels.get(name);
        const center = part.box.getCenter(new THREE.Vector3()).addScaledVector(part.offset, amount);
        projected.copy(center).applyMatrix4(stage.model.matrixWorld).project(stage.camera);
        const x = (projected.x * 0.5 + 0.5) * width + canvasRect.left - listRect.left;
        const y = (-projected.y * 0.5 + 0.5) * height + canvasRect.top - listRect.top;
        label.style.transform = `translate(${x}px, ${y}px) translate(-50%, -150%)`;
        label.classList.toggle("is-on", amount > 0.85);
      }
    };
  });
}

async function setupStages() {
  if (!webglAvailable()) {
    document.documentElement.classList.add("no-webgl");
    return;
  }
  const loops = [];
  const heroCanvas = document.querySelector('[data-stage="hero"]');
  const latchCanvas = document.querySelector('[data-stage="latch"]');
  const tasks = [];
  if (heroCanvas) tasks.push(setupHeroStage(heroCanvas).then((loop) => loops.push(loop)));
  if (latchCanvas) tasks.push(setupLatchStage(latchCanvas).then((loop) => loops.push(loop)));
  const start = performance.now();
  const tick = (now) => {
    loops.forEach((loop) => loop(now - start));
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  try {
    await Promise.all(tasks);
  } catch {
    document.documentElement.classList.add("no-webgl");
  }
}

function sentence() {
  const text = document.querySelector("[data-words]");
  const after = document.querySelector("[data-after]");
  if (!text) return;
  const section = text.closest(".sentence");
  const words = text.textContent.split(" ");
  text.innerHTML = words.map((word) => `<span class="w">${word}</span>`).join(" ");
  const spans = [...text.querySelectorAll(".w")];
  const update = () => {
    const progress = reducedMotion ? 1 : sectionProgress(section);
    const lit = Math.round(smooth(progress / 0.72) * spans.length);
    spans.forEach((span, index) => span.classList.toggle("is-lit", index < lit));
    after.classList.toggle("is-on", progress > 0.78);
  };
  window.addEventListener("scroll", update, { passive: true });
  update();
}

function appShot() {
  const shot = document.querySelector(".app-shot");
  if (!shot || reducedMotion) return;
  const update = () => {
    const rect = shot.getBoundingClientRect();
    const t = ease(clamp((window.innerHeight - rect.top) / (window.innerHeight * 0.9)));
    shot.style.setProperty("--rise", `${(1 - t) * 120}px`);
    shot.style.setProperty("--grow", String(0.9 + t * 0.1));
  };
  window.addEventListener("scroll", update, { passive: true });
  update();
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
    THICKNESS: "plate, stem, arm and lip, mm",
    PLATE_LEN: "screw plate behind the stem, mm",
    HOOK_GAP: "arm top to desk underside, mm",
    ARM_LEN: "hook arm from the stem, mm",
    LIP_H: "retaining lip above the arm, mm"
  };
  const order = ["WIDTH", "THICKNESS", "PLATE_LEN", "HOOK_GAP", "ARM_LEN", "LIP_H"];
  let lastChanged = null;
  const format = (value) => Number(value).toFixed(1);

  const renderCode = () => {
    code.innerHTML = order.map((name) => {
      const left = `${name} = `;
      const value = format(params[name]);
      const pad = " ".repeat(Math.max(1, 20 - left.length - value.length));
      const flash = name === lastChanged ? " is-flash" : "";
      return `${left}<span class="n${flash}" data-n="${name}">${value}</span>${pad}<span class="c"># ${comments[name]}</span>`;
    }).join("\n");
    if (lastChanged) {
      requestAnimationFrame(() => code.querySelector(`[data-n="${lastChanged}"]`)?.classList.remove("is-flash"));
    }
  };

  const rounded = (points, radii) => {
    let path = "";
    points.forEach((current, index) => {
      const previous = points[(index - 1 + points.length) % points.length];
      const next = points[(index + 1) % points.length];
      const toPrevious = [previous[0] - current[0], previous[1] - current[1]];
      const toNext = [next[0] - current[0], next[1] - current[1]];
      const lengthPrevious = Math.hypot(...toPrevious);
      const lengthNext = Math.hypot(...toNext);
      const r = Math.min(radii[index] || 0, lengthPrevious / 2, lengthNext / 2);
      const start = [current[0] + toPrevious[0] / lengthPrevious * r, current[1] + toPrevious[1] / lengthPrevious * r];
      const end = [current[0] + toNext[0] / lengthNext * r, current[1] + toNext[1] / lengthNext * r];
      path += `${index === 0 ? "M" : "L"}${start[0].toFixed(2)} ${start[1].toFixed(2)} Q${current[0].toFixed(2)} ${current[1].toFixed(2)} ${end[0].toFixed(2)} ${end[1].toFixed(2)} `;
    });
    return `${path}Z`;
  };

  const arrow = (x, y, angle) => {
    const a = [x + Math.cos(angle + 0.42) * 2.2, y + Math.sin(angle + 0.42) * 2.2];
    const b = [x + Math.cos(angle - 0.42) * 2.2, y + Math.sin(angle - 0.42) * 2.2];
    return `<path class="arrow" d="M${x} ${y} L${a[0]} ${a[1]} L${b[0]} ${b[1]} Z"/>`;
  };
  const horizontal = (x1, x2, y, label, live) => `<line class="dimline" x1="${x1}" y1="${y}" x2="${x2}" y2="${y}"/>${arrow(x1, y, 0)}${arrow(x2, y, Math.PI)}<text x="${(x1 + x2) / 2}" y="${y - 1.4}" text-anchor="middle" class="${live ? "is-live" : ""}">${label}</text>`;
  const vertical = (x, y1, y2, label, live) => `<line class="dimline" x1="${x}" y1="${y1}" x2="${x}" y2="${y2}"/>${arrow(x, y1, Math.PI / 2)}${arrow(x, y2, -Math.PI / 2)}<text x="${x + 1.6}" y="${(y1 + y2) / 2 + 1.5}" class="${live ? "is-live" : ""}">${label}</text>`;
  const ext = (x1, y1, x2, y2) => `<line class="ext" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;

  const render = () => {
    const { THICKNESS: t, PLATE_LEN: p, HOOK_GAP: gap, ARM_LEN: arm, LIP_H: lip } = params;
    const height = 2 * t + gap;
    const X = (x) => 62 + x;
    const Y = (z) => 14 - z;
    const points = [
      [-p, 0], [t, 0], [t, -(t + gap)], [arm - t, -(t + gap)], [arm - t, -(t + gap) + lip],
      [arm, -(t + gap) + lip], [arm, -height], [0, -height], [0, -t], [-p, -t]
    ].map(([x, z]) => [X(x), Y(z)]);
    const radii = [1, 0, 8, 1.2, 2.5, 2.5, 3, 8 + t, 6, 1];
    const holes = [-p * 0.28, -p * 0.72].map((x) => {
      const hx = X(x);
      return `<line class="hidden" x1="${hx - 2.25}" y1="${Y(0)}" x2="${hx - 2.25}" y2="${Y(-t) - 2}"/><line class="hidden" x1="${hx + 2.25}" y1="${Y(0)}" x2="${hx + 2.25}" y2="${Y(-t) - 2}"/><path class="hidden" d="M${hx - 4.3} ${Y(-t)} L${hx - 2.25} ${Y(-t) - 2} M${hx + 4.3} ${Y(-t)} L${hx + 2.25} ${Y(-t) - 2}"/><line class="axis" x1="${hx}" y1="${Y(0) - 3}" x2="${hx}" y2="${Y(-t) + 3}"/>`;
    }).join("");
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
      vertical(X(-p) - 7, Y(0), Y(-height), format(height), lastChanged === "HOOK_GAP" || lastChanged === "THICKNESS"),
      ext(X(-p) - 1, Y(-t), X(-p) - 9, Y(-t)),
      ext(X(0) - 1, Y(-height), X(-p) - 9, Y(-height))
    ].join("");
    svg.innerHTML = `<defs><pattern id="hatch" width="2.2" height="2.2" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="2.2" stroke="#86868b" stroke-width="0.35"/></pattern></defs><rect class="desk" x="${X(-p - 8)}" y="${Y(0) - 5}" width="${p + 106}" height="5"/><path class="body" d="${rounded(points, radii)}"/>${holes}${dims}`;
    svg.setAttribute("viewBox", `0 -2 ${X(arm) + 40} ${Math.max(below + 16, 100) + 2}`);
    total.textContent = `Overall height ${format(height)} mm`;
  };

  const syncFill = (input) => {
    input.style.setProperty("--fill", `${((input.value - input.min) / (input.max - input.min)) * 100}%`);
  };

  inputs.forEach((input) => {
    syncFill(input);
    input.addEventListener("input", () => {
      params[input.dataset.param] = Number(input.value);
      lastChanged = input.dataset.param;
      document.querySelector(`[data-out="${input.dataset.param}"]`).textContent = `${input.value} mm`;
      syncFill(input);
      render();
      renderCode();
    });
  });
  render();
  renderCode();
}

function sheets() {
  const stage = document.querySelector("[data-sheets]");
  if (!stage) return;
  const images = [...stage.querySelectorAll("img")];
  const chips = [...document.querySelectorAll("[data-sheet]")];
  const select = (index) => {
    images.forEach((image, imageIndex) => image.classList.toggle("is-on", imageIndex === index));
    chips.forEach((chip) => chip.setAttribute("aria-selected", String(Number(chip.dataset.sheet) === index)));
  };
  chips.forEach((chip) => chip.addEventListener("click", () => select(Number(chip.dataset.sheet))));
}

function film() {
  const dialog = document.querySelector("[data-film]");
  const video = dialog?.querySelector("[data-film-video]");
  if (!dialog) return;
  document.querySelector("[data-film-open]")?.addEventListener("click", () => {
    dialog.showModal();
    video.play().catch(() => {});
  });
  dialog.querySelector("[data-film-close]").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });
  dialog.addEventListener("close", () => video.pause());
}

function copyButtons() {
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(button.parentElement.querySelector("code").textContent);
        button.classList.add("is-copied");
        setTimeout(() => button.classList.remove("is-copied"), 1400);
      } catch {
        button.classList.remove("is-copied");
      }
    });
  });
}

function reveals() {
  if (reducedMotion) return;
  const targets = document.querySelectorAll(".tile-head, .shot-copy, .code-stage, .film-frame, .specs, .chips, .sheet-stage, .bento-title, .card, .steps li");
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-in");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.15 });
  targets.forEach((target) => {
    target.classList.add("rise");
    observer.observe(target);
  });
}

setupStages();
sentence();
appShot();
parameterDrawing();
sheets();
film();
copyButtons();
reveals();
