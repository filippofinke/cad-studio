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

const partColors = {};

const partLabels = {
  Housing: "Housing",
  Lid: "Lid",
  Plunger: "Plunger",
  Pin: "Follower pin",
  Spring: "Spring"
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
  const ghost = (canvas.dataset.ghost || "").split(",").filter(Boolean);
  const lifted = canvas.dataset.lift || "";
  const zoomSetting = Number(canvas.dataset.zoom || 1);
  const zoomFor = () => (stage.camera.aspect < 1.2 ? Math.max(zoomSetting, 1) : zoomSetting);
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
      if (ghost.includes(child.userData.part)) {
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
        stage.frame((0.9 - scroll * 0.12 + (1 - intro) * 0.4) * zoomFor(), 0.42 + scroll * 0.25);
      } else {
        stage.pivot.rotation.y = smoothX * 0.3;
        stage.pivot.rotation.x = 0;
        stage.frame(1.25 * zoomFor(), 0.95 + smoothY * 0.2);
      }
      stage.render();
      if (readout && player && time - lastReadout > 120) {
        lastReadout = time;
        const sample = player.sample(seconds);
        readout.querySelectorAll("[data-value]").forEach((element) => {
          const value = sample.values[element.dataset.value];
          if (value !== undefined) element.textContent = value.toFixed(Number(element.dataset.decimals || 0)).replace("-", "−");
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
    const name = child.userData.part || child.name;
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
    const box = new THREE.Box3();
    for (const mesh of part.meshes) {
      box.union(new THREE.Box3().setFromBufferAttribute(mesh.geometry.attributes.position).applyMatrix4(mesh.matrix));
    }
    const floor = box.min.z;
    const flip = part.meshes.length === 1 && isTopHeavy(part.meshes[0].geometry.attributes.position, box, part.meshes[0].position);
    if (flip) {
      const origin = part.meshes[0].position;
      box.set(
        new THREE.Vector3(box.min.x, 2 * origin.y - box.max.y, 2 * origin.z - box.max.z),
        new THREE.Vector3(box.max.x, 2 * origin.y - box.min.y, 2 * origin.z - box.min.z)
      );
    }
    items.push({ meshes: part.meshes, box, flip, floor, size: box.getSize(new THREE.Vector3()) });
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
  const overall = items.reduce((box, item) => box.union(item.box.clone()), new THREE.Box3());
  const home = overall.getCenter(new THREE.Vector3());
  const middle = extent.getCenter(new THREE.Vector2()).sub(new THREE.Vector2(home.x, home.y));
  const offsets = new Map();
  const flips = new Set();
  for (const { item, x, y } of placed) {
    const center = item.box.getCenter(new THREE.Vector3());
    const offset = new THREE.Vector3(x - middle.x - center.x, y - middle.y - center.y, floor - item.box.min.z);
    for (const mesh of item.meshes) {
      offsets.set(mesh, offset);
      if (item.flip) flips.add(mesh);
    }
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
