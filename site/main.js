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
