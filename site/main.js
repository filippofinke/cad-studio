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
  Sun: "Sun gear",
  "Planet 1": "Planets ×4",
  Ring: "Ring gear",
  Carrier: "Carrier"
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
    sample(time) {
      const t = duration > 0 ? ((time % duration) + duration) % duration : 0;
      const upper = Math.max(1, frames.findIndex((frame) => frame.t >= t));
      const next = frames[Math.min(upper, frames.length - 1)];
      const previous = frames[upper - 1] || next;
      const span = next.t - previous.t;
      const f = span > 0 ? clamp((t - previous.t) / span) : 0;
      const values = {};
      for (const key of Object.keys(next.values || {})) {
        const a = previous.values?.[key] ?? next.values[key];
        values[key] = a + (next.values[key] - a) * f;
      }
      return { values, label: (f < 0.5 ? previous : next).label };
    },
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

function setupAnimatedStage(canvas, mode) {
  const stage = new Stage(canvas, { url: canvas.dataset.model });
  const section = canvas.closest("section");
  const ghost = canvas.dataset.ghost || "";
  const lifted = canvas.dataset.lift || "";
  const readout = mode === "motion" ? document.querySelector("[data-readout]") : null;
  const phase = mode === "motion" ? document.querySelector("[data-phase]") : null;
  const animation = canvas.dataset.animation
    ? fetch(canvas.dataset.animation).then((response) => (response.ok ? response.json() : null)).catch(() => null)
    : Promise.resolve(null);
  let pointerX = 0;
  let pointerY = 0;
  let smoothX = 0;
  let smoothY = 0;
  let lastReadout = 0;
  window.addEventListener("pointermove", (event) => {
    pointerX = event.clientX / window.innerWidth - 0.5;
    pointerY = event.clientY / window.innerHeight - 0.5;
  }, { passive: true });
  return Promise.all([stage.ready, animation]).then(([, study]) => {
    const player = study?.frames?.length > 1 ? motionPlayer(study) : null;
    const meshes = [];
    const height = new THREE.Box3().setFromObject(stage.model).getSize(new THREE.Vector3()).y;
    const lift = new THREE.Matrix4();
    stage.model.traverse((child) => {
      if (!child.isMesh) return;
      child.matrixAutoUpdate = false;
      child.updateMatrix();
      const name = child.name || child.parent?.name || "";
      if (name === ghost) {
        child.material.transparent = true;
        child.material.opacity = 0.22;
        child.material.depthWrite = false;
      }
      meshes.push({ mesh: child, base: child.matrix.clone(), name });
    });
    return (time) => {
      if (!stage.visible) return;
      smoothX += (pointerX - smoothX) * 0.05;
      smoothY += (pointerY - smoothY) * 0.05;
      const seconds = reducedMotion ? 1.5 : time / 1000;
      const scroll = mode === "hero" ? clamp(-section.getBoundingClientRect().top / section.offsetHeight) : 0;
      const intro = reducedMotion || mode !== "hero" ? 1 : ease(time / 2200);
      const raise = height * (0.25 + 0.75 * intro) * (1 + scroll * 1.2);
      for (const { mesh, base, name } of meshes) {
        const pose = player ? player.pose(name, seconds) : new THREE.Matrix4();
        lift.makeTranslation(0, 0, name === lifted ? raise : 0);
        mesh.matrix.multiplyMatrices(lift, pose).multiply(base);
      }
      if (mode === "hero") {
        stage.pivot.rotation.y = -0.5 + intro * 0.35 + (reducedMotion ? 0 : time * 0.00005) + scroll * 0.9 + smoothX * 0.45;
        stage.pivot.rotation.x = smoothY * 0.1;
        stage.frame(0.9 - scroll * 0.12 + (1 - intro) * 0.4, 0.42 + scroll * 0.25);
      } else {
        stage.pivot.rotation.y = smoothX * 0.3;
        stage.pivot.rotation.x = 0;
        stage.frame(1.25, 0.95 + smoothY * 0.2);
      }
      stage.render();
      if (readout && player && time - lastReadout > 120) {
        lastReadout = time;
        const sample = player.sample(seconds);
        readout.querySelectorAll("[data-value]").forEach((element) => {
          const value = sample.values[element.dataset.value];
          if (value !== undefined) element.textContent = Math.round(value).toString().replace("-", "−");
        });
        if (phase && sample.label) phase.textContent = sample.label;
      }
    };
  });
}

function explodedOffsets(model) {
  const groups = new Map();
  model.updateMatrixWorld(true);
  model.traverse((child) => {
    if (!child.isMesh) return;
    const name = child.name || child.userData.part;
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

function plateLayout(parts) {
  const items = [];
  for (const [, part] of parts) {
    for (const mesh of part.meshes) {
      const box = new THREE.Box3().setFromBufferAttribute(mesh.geometry.attributes.position).applyMatrix4(mesh.matrix);
      const floor = box.min.z;
      const flip = isTopHeavy(mesh.geometry.attributes.position, box, mesh.position);
      if (flip) {
        box.set(
          new THREE.Vector3(box.min.x, 2 * mesh.position.y - box.max.y, 2 * mesh.position.z - box.max.z),
          new THREE.Vector3(box.max.x, 2 * mesh.position.y - box.min.y, 2 * mesh.position.z - box.min.z)
        );
      }
      items.push({ mesh, box, flip, floor, size: box.getSize(new THREE.Vector3()) });
    }
  }
  const floor = Math.min(...items.map((item) => item.floor));
  const gap = Math.max(...items.map((item) => item.size.x)) * 0.12;
  const rowWidth = Math.max(...items.map((item) => item.size.x)) * 2.3;
  items.sort((a, b) => b.size.x * b.size.y - a.size.x * a.size.y);
  let x = 0;
  let y = 0;
  let rowHeight = 0;
  const placed = [];
  for (const item of items) {
    if (x > 0 && x + item.size.x > rowWidth) {
      x = 0;
      y += rowHeight + gap;
      rowHeight = 0;
    }
    placed.push({ item, x: x + item.size.x / 2, y: y + item.size.y / 2 });
    x += item.size.x + gap;
    rowHeight = Math.max(rowHeight, item.size.y);
  }
  const extent = new THREE.Box2();
  for (const { item, x, y } of placed) {
    extent.expandByPoint(new THREE.Vector2(x - item.size.x / 2, y - item.size.y / 2));
    extent.expandByPoint(new THREE.Vector2(x + item.size.x / 2, y + item.size.y / 2));
  }
  const middle = extent.getCenter(new THREE.Vector2());
  const offsets = new Map();
  const flips = new Set();
  for (const { item, x, y } of placed) {
    const center = item.box.getCenter(new THREE.Vector3());
    offsets.set(item.mesh, new THREE.Vector3(x - middle.x - center.x, y - middle.y - center.y, floor - item.box.min.z));
    if (item.flip) flips.add(item.mesh);
  }
  const size = extent.getSize(new THREE.Vector2());
  return { offsets, flips, radius: Math.hypot(size.x, size.y) / 2, span: Math.max(size.x, size.y) };
}

function isTopHeavy(positions, box, origin) {
  const band = (box.max.z - box.min.z) * 0.05;
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  const c = new THREE.Vector3();
  const normal = new THREE.Vector3();
  let top = 0;
  let bottom = 0;
  for (let index = 0; index + 2 < positions.count; index += 3) {
    a.fromBufferAttribute(positions, index);
    b.fromBufferAttribute(positions, index + 1);
    c.fromBufferAttribute(positions, index + 2);
    normal.crossVectors(b.clone().sub(a), c.clone().sub(a));
    const area = normal.length() / 2;
    if (!area) continue;
    const z = (a.z + b.z + c.z) / 3 + origin.z;
    const facing = normal.z / (area * 2);
    if (facing > 0.95 && z > box.max.z - band) top += area;
    if (facing < -0.95 && z < box.min.z + band) bottom += area;
  }
  return top > bottom * 2;
}

function printBed(stage, footprint) {
  const box = new THREE.Box3().setFromObject(stage.model);
  const size = box.getSize(new THREE.Vector3());
  const span = Math.ceil(footprint * 1.3 / 10) * 10;
  const y = box.min.y - 0.05;
  const group = new THREE.Group();
  const materials = [];
  const fade = (material, opacity) => {
    material.transparent = true;
    material.depthWrite = false;
    material.userData.opacity = opacity;
    materials.push(material);
    return material;
  };
  const plate = new THREE.Mesh(
    new THREE.PlaneGeometry(span, span),
    fade(new THREE.MeshBasicMaterial({ color: "#141416" }), 1)
  );
  plate.rotation.x = -Math.PI / 2;
  plate.renderOrder = -2;
  const grid = new THREE.GridHelper(span, span / 10, "#5a5a5e", "#3a3a3c");
  grid.position.y = 0.05;
  grid.renderOrder = -1;
  fade(grid.material, 1);
  const half = span / 2;
  const outline = new THREE.LineLoop(
    new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-half, 0.1, -half), new THREE.Vector3(half, 0.1, -half),
      new THREE.Vector3(half, 0.1, half), new THREE.Vector3(-half, 0.1, half)
    ]),
    fade(new THREE.LineBasicMaterial({ color: "#2997ff" }), 1)
  );
  group.add(plate, grid, outline);
  group.position.y = y;
  group.visible = false;
  stage.pivot.add(group);
  return {
    show(amount) {
      group.visible = amount > 0.001;
      group.position.y = y - (1 - amount) * size.y * 0.6;
      for (const material of materials) material.opacity = material.userData.opacity * amount;
    }
  };
}

function setupPartsStage(canvas) {
  const stage = new Stage(canvas, { url: canvas.dataset.model, fov: 24 });
  const section = canvas.closest(".parts");
  const lines = [...section.querySelectorAll("[data-line]")];
  const labelList = section.querySelector("[data-part-labels]");
  return stage.ready.then(() => {
    const parts = explodedOffsets(stage.model);
    const labels = new Map();
    for (const [name] of parts) {
      if (!partLabels[name]) continue;
      const item = document.createElement("li");
      item.textContent = partLabels[name];
      labelList.appendChild(item);
      labels.set(name, item);
    }
    const origins = new Map();
    for (const [, part] of parts) {
      for (const mesh of part.meshes) origins.set(mesh, mesh.position.clone());
    }
    const projected = new THREE.Vector3();
    const layout = plateLayout(parts);
    const bed = printBed(stage, layout.span);
    const zoom = layout.radius / stage.radius;
    return () => {
      if (!stage.visible) return;
      const progress = sectionProgress(section);
      const amount = smooth((progress - 0.14) / 0.26);
      const settle = smooth((progress - 0.5) / 0.3);
      const index = progress < 0.16 ? 0 : progress < 0.55 ? 1 : 2;
      bed.show(settle);
      lines.forEach((line, lineIndex) => line.classList.toggle("is-on", lineIndex === index));
      for (const [, part] of parts) {
        for (const mesh of part.meshes) {
          mesh.position.copy(origins.get(mesh)).addScaledVector(part.offset, amount * (1 - settle)).addScaledVector(layout.offsets.get(mesh), settle);
          if (layout.flips.has(mesh)) mesh.rotation.x = Math.PI * settle;
        }
      }
      stage.pivot.rotation.y = -0.4 + progress * 0.8;
      const spread = 0.95 + amount * 0.55;
      stage.frame(spread + (zoom * 1.25 - spread) * settle, 0.62 - progress * 0.2 + settle * 0.5);
      stage.render();
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const canvasRect = canvas.getBoundingClientRect();
      const listRect = labelList.getBoundingClientRect();
      for (const [name, part] of parts) {
        const label = labels.get(name);
        if (!label) continue;
        const center = part.box.getCenter(new THREE.Vector3()).addScaledVector(part.offset, amount * (1 - settle)).addScaledVector(layout.offsets.get(part.meshes[0]), settle);
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
  const tasks = [];
  const add = (selector, setup) => {
    const canvas = document.querySelector(selector);
    if (canvas) tasks.push(setup(canvas).then((loop) => loops.push(loop)));
  };
  add('[data-stage="hero"]', (canvas) => setupAnimatedStage(canvas, "hero"));
  add('[data-stage="parts"]', setupPartsStage);
  add('[data-stage="motion"]', (canvas) => setupAnimatedStage(canvas, "motion"));
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

function gearDrawing() {
  const svg = document.querySelector("[data-gears]");
  if (!svg) return;
  const ratioLabel = document.querySelector("[data-gear-ratio]");
  const check = document.querySelector("[data-gear-check]");
  const dims = document.querySelector("[data-gear-dims]");
  const inputs = [...document.querySelectorAll("[data-param]")];
  const params = { MODULE: 1.5, SUN_TEETH: 12, PLANET_TEETH: 12, NUM_PLANETS: 4 };
  let visible = false;
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
  }).observe(svg);

  const gearPath = (cx, cy, teeth, module, phase, internal) => {
    const pitch = module * teeth / 2;
    const tip = internal ? pitch - module * 0.8 : pitch + module * 0.9;
    const root = internal ? pitch + module * 1.25 : pitch - module * 1.25;
    const step = (Math.PI * 2) / teeth;
    const points = [];
    for (let index = 0; index < teeth; index++) {
      const angle = phase + index * step;
      for (const [radius, offset] of [[root, -0.3], [tip, -0.13], [tip, 0.13], [root, 0.3]]) {
        points.push(`${(cx + Math.cos(angle + offset * step) * radius).toFixed(2)},${(cy + Math.sin(angle + offset * step) * radius).toFixed(2)}`);
      }
    }
    return `M${points.join("L")}Z`;
  };

  const circle = (cx, cy, r) => `M${cx - r},${cy}a${r},${r} 0 1,0 ${r * 2},0a${r},${r} 0 1,0 ${-r * 2},0Z`;

  let geometry = null;
  const update = () => {
    const { MODULE: m, SUN_TEETH: zs, PLANET_TEETH: zp, NUM_PLANETS: n } = params;
    const zr = zs + 2 * zp;
    const distance = m * (zs + zp) / 2;
    const ringOuter = m * zr / 2 + m * 1.25 + m * 2.5;
    const spacing = 2 * distance * Math.sin(Math.PI / n);
    const planetTip = 2 * (m * zp / 2 + m * 0.9);
    const even = (zs + zr) % n === 0;
    const clear = spacing > planetTip + 0.4;
    geometry = { m, zs, zp, zr, n, distance, ringOuter, scale: 52 / ringOuter };
    const ratio = 1 + zr / zs;
    ratioLabel.textContent = `Ratio ${ratio.toFixed(ratio % 1 === 0 ? 0 : 2)} : 1 · ring ${zr} teeth`;
    dims.textContent = `${(ringOuter * 2).toFixed(1)} × ${(ringOuter * 2).toFixed(1)} mm`;
    check.textContent = !clear ? "Planets would collide" : even ? "Planets assemble evenly" : "Planets can't be spaced evenly";
    check.classList.toggle("is-bad", !clear || !even);
  };

  const draw = (time) => {
    if (!geometry) return;
    const { m, zs, zp, zr, n, distance, ringOuter, scale } = geometry;
    const carrier = reducedMotion ? 0 : time * 0.00025;
    const sun = carrier * (1 + zr / zs);
    const parts = [];
    parts.push(`<path class="g-ring" fill-rule="evenodd" d="${circle(0, 0, ringOuter * scale)}${gearPath(0, 0, zr, m * scale, zp % 2 === 0 ? 0 : Math.PI / zr, true)}"/>`);
    for (let index = 0; index < n; index++) {
      const phi = carrier + index * (Math.PI * 2) / n;
      const x = Math.cos(phi) * distance * scale;
      const y = Math.sin(phi) * distance * scale;
      const spin = phi + Math.PI - Math.PI / zp - (zs / zp) * (phi - sun);
      parts.push(`<path class="g-planet" d="${gearPath(x, y, zp, m * scale, spin, false)}"/><circle class="g-pin" cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${(m * scale * 1.6).toFixed(2)}"/>`);
    }
    parts.push(`<path class="g-sun" d="${gearPath(0, 0, zs, m * scale, sun, false)}"/><circle class="g-hub" r="${(m * scale * 2.4).toFixed(2)}"/>`);
    parts.push(`<circle class="g-carrier" r="${(distance * scale).toFixed(2)}"/>`);
    svg.innerHTML = parts.join("");
  };

  const loop = (time) => {
    if (visible || time < 100) draw(time);
    requestAnimationFrame(loop);
  };

  inputs.forEach((input) => {
    const sync = () => input.style.setProperty("--fill", `${((input.value - input.min) / (input.max - input.min)) * 100}%`);
    sync();
    input.addEventListener("input", () => {
      params[input.dataset.param] = Number(input.value);
      document.querySelector(`[data-out="${input.dataset.param}"]`).textContent = input.value;
      sync();
      update();
    });
  });
  update();
  requestAnimationFrame(loop);
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
  const targets = document.querySelectorAll(".tile-head, .shot-copy, .param-win, .film-frame, .specs, .chips, .sheet-stage, .bento-title, .card, .steps li");
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
gearDrawing();
sheets();
film();
copyButtons();
reveals();
