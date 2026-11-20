// The live demo: one duck moving at a 24 fps source's rate, and the same motion as
// MetalDuck shows it, with capture capped at 30 fps and the chosen multiplier.
// Blue marks are captured frames; orange marks are frames built between them.

import { useEffect, useRef, useState, type KeyboardEvent } from 'react';

const SOURCE_FPS = 24;
const CAPTURE_CAP = 30;
const PERIOD = 2.6;
const BLUE = '#5aa2ff';
const ORANGE = '#ff7a2e';
const MULTIPLIERS = [1, 2, 3, 4] as const;
const REFRESH_RATES = [60, 75, 90, 100, 120, 144, 165, 240];

const outputFor = (m: number) => (m === 1 ? SOURCE_FPS : CAPTURE_CAP * m);

export default function FrameDemo() {
  const sourceRef = useRef<HTMLCanvasElement>(null);
  const duckRef = useRef<HTMLCanvasElement>(null);
  const radios = useRef<(HTMLButtonElement | null)[]>([]);
  const [multiplier, setMultiplier] = useState(4);
  const [paused, setPaused] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const [refresh, setRefresh] = useState(60);
  const state = useRef({ multiplier, paused, start: performance.now(), pausedAt: performance.now() + 700 });

  // Keep the animation loop reading the latest choices.
  useEffect(() => {
    const s = state.current;
    if (paused && !s.paused) s.pausedAt = performance.now();
    if (!paused && s.paused) s.start += performance.now() - s.pausedAt;
    s.paused = paused;
    s.multiplier = multiplier;
  }, [paused, multiplier]);

  // Measure the display, so the note is honest about what this screen can show. The median
  // frame interval ignores the hitches of a page that is still loading.
  useEffect(() => {
    const intervals: number[] = [];
    let last = 0;
    let id = 0;
    const tick = (now: number) => {
      if (last) intervals.push(now - last);
      last = now;
      if (intervals.length < 90) id = requestAnimationFrame(tick);
      else {
        intervals.sort((a, b) => a - b);
        const measured = 1000 / intervals[Math.floor(intervals.length / 2)];
        setRefresh(REFRESH_RATES.reduce((best, r) => (Math.abs(r - measured) < Math.abs(best - measured) ? r : best), 60));
      }
    };
    id = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(id);
  }, []);

  useEffect(() => {
    const duck = new Image();
    duck.src = '/assets/duck.png';
    const canvases = [sourceRef.current!, duckRef.current!];
    let lanes: { ctx: CanvasRenderingContext2D; width: number; height: number }[] = [];
    let visible = true;
    let raf = 0;

    const size = () => {
      const ratio = window.devicePixelRatio || 1;
      lanes = canvases.map(canvas => {
        const { width, height } = canvas.getBoundingClientRect();
        canvas.width = Math.round(width * ratio);
        canvas.height = Math.round(height * ratio);
        const ctx = canvas.getContext('2d')!;
        ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
        return { ctx, width, height };
      });
    };

    const position = (t: number, width: number) => {
      const margin = 46;
      return margin + (width - margin * 2) * (0.5 - 0.5 * Math.cos((2 * Math.PI * t) / PERIOD));
    };
    const quantize = (t: number, rate: number) => Math.floor(t * rate) / rate;

    const mark = (ctx: CanvasRenderingContext2D, x: number, y: number, color: string, alpha: number, s = 8) => {
      ctx.globalAlpha = alpha;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.roundRect(x - s / 2, y - s / 2, s, s, 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    };

    const drawDuck = (ctx: CanvasRenderingContext2D, x: number, y: number) => {
      const s = 56;
      if (duck.complete && duck.naturalWidth) ctx.drawImage(duck, x - s / 2, y - s / 2 - 4, s, s);
    };

    const drawLane = (lane: (typeof lanes)[number], t: number, generated: boolean) => {
      const { ctx, width, height } = lane;
      const m = state.current.multiplier;
      ctx.clearRect(0, 0, width, height);
      const trackY = height - 30;
      ctx.strokeStyle = 'rgba(255,255,255,0.08)';
      ctx.setLineDash([3, 9]);
      ctx.beginPath();
      ctx.moveTo(24, trackY);
      ctx.lineTo(width - 24, trackY);
      ctx.stroke();
      ctx.setLineDash([]);

      const lastCapture = quantize(t, SOURCE_FPS);
      for (let i = 0; i < 6; i += 1) mark(ctx, position(lastCapture - i / SOURCE_FPS, width), trackY, BLUE, 0.9 - i * 0.14);

      if (!generated || m === 1) {
        drawDuck(ctx, position(lastCapture, width), height - 56);
        return;
      }
      const rate = outputFor(m);
      const lastOut = quantize(t, rate);
      const count = Math.ceil((6 / SOURCE_FPS) * rate);
      for (let i = 1; i < count; i += 1) {
        const ot = lastOut - i / rate;
        const onCapture = Math.abs(ot * SOURCE_FPS - Math.round(ot * SOURCE_FPS)) < 0.02;
        if (!onCapture) mark(ctx, position(ot, width), trackY + 12, ORANGE, Math.max(0.15, 0.85 - (i / count) * 0.8), 4);
      }
      drawDuck(ctx, position(lastOut, width), height - 56);
    };

    const now = () => {
      const s = state.current;
      return ((s.paused ? s.pausedAt : performance.now()) - s.start) / 1000;
    };
    const loop = () => {
      if (visible && lanes.length === 2) {
        const t = now();
        drawLane(lanes[0], t, false);
        drawLane(lanes[1], t, true);
      }
      raf = requestAnimationFrame(loop);
    };

    size();
    const observer = new IntersectionObserver(entries => {
      visible = entries.some(e => e.isIntersecting);
    });
    observer.observe(canvases[1]);
    window.addEventListener('resize', size);
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      observer.disconnect();
      window.removeEventListener('resize', size);
    };
  }, []);

  const out = outputFor(multiplier);
  const note =
    multiplier === 1
      ? 'Frame generation off: you see only the 24 frames the source delivers.'
      : `Capture capped at ${CAPTURE_CAP} fps, ${multiplier}× generation: ${CAPTURE_CAP} × ${multiplier} = ${out} frames a second.` +
        (out > refresh ? ` This display shows ${refresh} of them.` : '');

  const onKey = (event: KeyboardEvent, index: number) => {
    const step = ({ ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 } as Record<string, number>)[event.key];
    if (!step) return;
    event.preventDefault();
    const next = (index + step + MULTIPLIERS.length) % MULTIPLIERS.length;
    setMultiplier(MULTIPLIERS[next]);
    radios.current[next]?.focus();
  };

  return (
    <figure className="demo" aria-labelledby="demo-caption">
      <div className="demo-head">
        <p id="demo-caption">
          The same motion, twice. Blue marks are frames your source delivers; orange ones are frames MetalDuck builds
          between them.
        </p>
        <div className="segmented" role="radiogroup" aria-label="Frame generation multiplier">
          {MULTIPLIERS.map((m, i) => (
            <button
              key={m}
              ref={el => {
                radios.current[i] = el;
              }}
              role="radio"
              aria-checked={multiplier === m}
              tabIndex={multiplier === m ? 0 : -1}
              data-off={m === 1 || undefined}
              onClick={() => setMultiplier(m)}
              onKeyDown={e => onKey(e, i)}
            >
              {m === 1 ? 'Off' : `${m}×`}
            </button>
          ))}
        </div>
      </div>
      <div className="lane">
        <div className="lane-label">
          <span className="dot dot-capture" />
          Your source<b>24 fps</b>
        </div>
        <canvas ref={sourceRef} aria-hidden="true" />
      </div>
      <div className="lane">
        <div className="lane-label">
          <span className="dot dot-generate" />
          With MetalDuck<b>{out} fps</b>
        </div>
        <canvas ref={duckRef} aria-hidden="true" />
      </div>
      <figcaption>
        <span aria-live="polite">{note}</span>
        <button className="link-button" type="button" onClick={() => setPaused(p => !p)}>
          {paused ? 'Play' : 'Pause'}
        </button>
      </figcaption>
    </figure>
  );
}
