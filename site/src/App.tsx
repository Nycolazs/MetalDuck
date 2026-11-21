import BlurText from './reactbits/BlurText';
import CountUp from './reactbits/CountUp';
import GlareHover from './reactbits/GlareHover';
import Magnet from './reactbits/Magnet';
import MetallicPaint from './reactbits/MetallicPaint';
import PixelTransition from './reactbits/PixelTransition';
import ShapeGrid from './reactbits/ShapeGrid';
import ShinyText from './reactbits/ShinyText';
import SpecularButton from './reactbits/SpecularButton';
import SpotlightCard from './reactbits/SpotlightCard';
import FrameDemo from './FrameDemo';

const DOWNLOAD = 'https://github.com/Nycolazs/MetalDuck/releases/latest';
const REPO = 'https://github.com/Nycolazs/MetalDuck';
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function DownloadButton({ label }: { label: string }) {
  return (
    <Magnet padding={60} magnetStrength={4} maxOffset={10}>
      <SpecularButton
        size="lg"
        radius={28}
        baseColor="#8f98a5"
        lineColor="#ffffff"
        textColor="#14171c"
        tint="#e4e8ee"
        tintOpacity={0.92}
        intensity={1.2}
        idleIntensity={0.45}
        autoAnimate={!reducedMotion}
        aria-label={`${label} (opens the GitHub release)`}
        onClick={() => window.location.assign(DOWNLOAD)}
      >
        {label}
      </SpecularButton>
    </Magnet>
  );
}

const profiles = [
  { name: 'Anime', use: '24 fps episodes and films', capture: 30, multiplier: 4 },
  { name: 'Games', use: 'Games that hold 60 but not 120', capture: 60, multiplier: 2 },
  { name: 'Video', use: '30 fps streams and recordings', capture: 30, multiplier: 2 }
];

const steps = [
  {
    title: 'Capture',
    tech: 'ScreenCaptureKit',
    text: 'Each frame arrives with the time it changed. A 24 fps video under a 30 fps cap keeps its own even 41.7 ms spacing instead of being snapped to a grid.',
    color: 'rgba(90, 162, 255, 0.22)'
  },
  {
    title: 'Measure the motion',
    tech: 'Vision optical flow',
    text: "Apple's Vision framework estimates how every part of the picture moved, forward and backward, in about 20 ms per pair on an M1 Pro.",
    color: 'rgba(90, 162, 255, 0.22)'
  },
  {
    title: 'Build the frame',
    tech: 'Metal',
    text: 'One compute shader moves the older frame forward and the newer one back to the exact moment on screen. Where the two disagree, it blends instead of showing a broken warp.',
    color: 'rgba(255, 122, 46, 0.22)'
  },
  {
    title: 'Upscale',
    tech: 'MetalFX Spatial',
    text: 'MetalFX scales the finished frame, so the upscaler works on the picture you actually watch.',
    color: 'rgba(255, 122, 46, 0.22)'
  }
];

const limits = [
  ['The picture runs a little behind', 'About one captured frame plus 25 ms. The next real frame has to arrive before the ones in between can be drawn.'],
  ['Very fast, small objects can smear', 'Something small that moves more than about 45 pixels between two captures is often missed, and that spot falls back to a blend.'],
  ['Covered windows may pause', 'Video keeps playing under the overlay, but some page animations stop when their window is covered, so there is nothing new to interpolate.'],
  ['Protected video shows black', "Some DRM-protected players can't be captured by any app, MetalDuck included."]
];

const faqs = [
  ["macOS says it can't check the app. How do I open it?", 'MetalDuck isn\'t notarized by Apple yet. Open the disk image, drag MetalDuck to Applications and open it once. When macOS stops it, go to System Settings, then Privacy & Security, and click Open Anyway next to MetalDuck.'],
  ['Why does it ask for Screen Recording?', "That is how any app reads another window's picture on macOS. Without it the capture stays empty. Nothing is recorded to disk or sent anywhere."],
  ['How do I stop it if the overlay covers everything?', 'Press Control-Option-Command-Escape. It always stops scaling, from any app. You can also set your own shortcut, or use Stop in the menu bar.'],
  ['Does it work with games?', 'Yes, with any game that runs in a window or on a display MetalDuck can capture. Because it only sees the finished picture, it works without game support, with the limits above.'],
  ['Is it really free?', 'Yes. MetalDuck is open source under the MIT license. The code, the issues and every release are on GitHub.']
];

export default function App() {
  return (
    <>
      <a className="skip" href="#main">Skip to content</a>

      <header className="nav">
        <a className="brand" href="#top" aria-label="MetalDuck home">
          <img src="/assets/duck.png" alt="" width="34" height="34" />
          <span>MetalDuck</span>
        </a>
        <nav aria-label="Sections">
          <a href="#how">How it works</a>
          <a href="#measured">Measured</a>
          <a href="#limits">Limits</a>
          <a href="#faq">FAQ</a>
        </nav>
        <a className="nav-download" href={DOWNLOAD}>Download</a>
      </header>

      <main id="main">
        <section className="hero" id="top">
          <ShapeGrid
            className="hero-grid"
            shape="square"
            cellSize={44}
            direction="diagonal"
            speed={0.25}
            lineColor="rgba(221, 225, 231, 0.07)"
            hoverColor="#5aa2ff"
            hoverFillColor="#5aa2ff"
            fillOpacity={0.12}
            trail={0.5}
            glow={0.3}
            radius={3}
            paused={reducedMotion}
          />
          <div className="hero-copy">
            <div className="h1" role="heading" aria-level={1}>
              <BlurText
                text="Turn a 24 fps video into 120 frames on your Mac."
                animateBy="words"
                direction="top"
                delay={70}
                trigger="load"
              />
            </div>
            <p className="lede">
              MetalDuck captures a window or your whole display, builds the frames in between the real ones, and
              upscales the picture with MetalFX. It runs on any app, no game or player support needed.
            </p>
            <div className="actions">
              <DownloadButton label="Download for Mac" />
              <a className="ghost" href={REPO}>Read the source</a>
            </div>
            <p className="fine">Free and MIT licensed. Version 1.3.2, for Apple silicon Macs on macOS 15 or later.</p>
          </div>
          <div className="hero-metal" aria-hidden="true">
            <MetallicPaint
              imageSrc="/assets/duck-mask.png"
              color="#e9edf2"
              scale={0.78}
              speed={0.7}
              mouseTilt={0.6}
              paused={reducedMotion}
            />
          </div>
        </section>

        <section className="demo-section" aria-label="Frame generation demo">
          <FrameDemo />
        </section>

        <section className="profiles" aria-labelledby="profiles-title">
          <div className="section-head">
            <h2 id="profiles-title">Pick a profile, choose a window, press Start.</h2>
            <p>Each profile is a starting point you can change. Output is always capture rate times the multiplier, so the number is never a guess.</p>
          </div>
          <ul className="profile-list">
            {profiles.map(p => (
              <li key={p.name}>
                <span className="profile-name">{p.name}</span>
                <span className="profile-for">{p.use}</span>
                <span className="profile-math">
                  {p.capture} × {p.multiplier} ={' '}
                  <b>
                    <CountUp mode="count" from={p.capture} to={p.capture * p.multiplier} duration={1.4} suffix=" fps" />
                  </b>
                </span>
              </li>
            ))}
          </ul>
        </section>

        <section className="how" id="how" aria-labelledby="how-title">
          <div className="section-head">
            <h2 id="how-title">How a frame gets made</h2>
            <p>MetalDuck never gets motion vectors from the app it watches. It measures the motion itself, between two real frames, and draws the moments in between.</p>
          </div>
          <ol className="pipeline">
            {steps.map((step, i) => (
              <li key={step.title}>
                <SpotlightCard className="step" spotlightColor={step.color}>
                  <span className={`step-number ${i >= 2 ? 'is-generated' : ''}`}>{i + 1}</span>
                  <h3>{step.title}</h3>
                  <p>{step.text}</p>
                  <span className="tech">{step.tech}</span>
                </SpotlightCard>
              </li>
            ))}
          </ol>
        </section>

        <section className="app" aria-labelledby="app-title">
          <div className="section-head">
            <h2 id="app-title">One window for everything</h2>
            <p>The controls and a live monitor share the same window. The picture itself appears in an overlay over the source, and clicks pass straight through to it.</p>
          </div>
          <div className="screens">
            <figure>
              <GlareHover width="100%" height="auto" background="transparent" borderColor="transparent" borderRadius="18px" glareOpacity={0.25} glareSize={260}>
                <img src="/assets/laptop-controls.png" alt="MetalDuck's control window on a MacBook, showing capture, frame generation and scaling settings" width="1000" height="640" loading="lazy" />
              </GlareHover>
              <figcaption>Capture, frame generation, scaling and dynamic resolution, with the result spelled out: 30 × 4 = 120 fps.</figcaption>
            </figure>
            <figure>
              <GlareHover width="100%" height="auto" background="transparent" borderColor="transparent" borderRadius="18px" glareOpacity={0.25} glareSize={260}>
                <img src="/assets/laptop-monitor.png" alt="MetalDuck's Monitor page on a MacBook, with frame rate and CPU charts and an event log" width="1000" height="640" loading="lazy" />
              </GlareHover>
              <figcaption>The Monitor shows capture, output and generated rates, CPU and memory, and whether each frame was warped or blended.</figcaption>
            </figure>
          </div>
        </section>

        <section className="measured" id="measured" aria-labelledby="measured-title">
          <div className="section-head">
            <h2 id="measured-title">Measured, not promised</h2>
            <p>Numbers from building version 1.3 on an M1 Pro: a 24 fps source, the Anime profile, 4× generation.</p>
          </div>
          <div className="measured-grid">
            <table>
              <caption className="visually-hidden">Before and after the 1.3 frame pipeline</caption>
              <thead>
                <tr><th scope="col" /><th scope="col">Before</th><th scope="col">1.3</th></tr>
              </thead>
              <tbody>
                <tr><th scope="row">Time between captured frames</th><td data-label="Before">33, 33, 33, then 67 ms</td><td data-label="1.3">41–42 ms</td></tr>
                <tr><th scope="row">Frames that reached the display</th><td data-label="Before">112–116 a second</td><td data-label="1.3">118–120 a second</td></tr>
                <tr><th scope="row">Average error of one motion step</th><td data-label="Before">2–3 ms</td><td data-label="1.3">0.4–1.2 ms</td></tr>
              </tbody>
            </table>
            <div className="psnr">
              <h3>How close the in-between frame is to the real one</h3>
              <p>A 40 px move, compared offline with a frame rendered at the true halfway point. Higher is closer.</p>
              <dl className="bars">
                {[
                  ['MetalDuck 1.3', 33.3],
                  ['Previous pipeline', 29.4],
                  ['Plain crossfade', 25.9]
                ].map(([label, value]) => (
                  <div key={label as string}>
                    <dt>{label}</dt>
                    <dd>
                      <span className="bar" style={{ ['--v' as string]: value }} />
                      <CountUp mode="count" from={20} to={value as number} decimals={1} duration={1.2} suffix=" dB" />
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          </div>
        </section>

        <section className="limits" id="limits" aria-labelledby="limits-title">
          <div className="section-head">
            <h2 id="limits-title">What it can't do</h2>
            <p>Desktop capture has no depth and no per-pixel motion from the game. Here is what that means in practice.</p>
          </div>
          <ul className="limit-list">
            {limits.map(([title, text]) => (
              <li key={title}>
                <h3>{title}</h3>
                <p>{text}</p>
              </li>
            ))}
          </ul>
        </section>

        <section className="faq" id="faq" aria-labelledby="faq-title">
          <h2 id="faq-title">Questions</h2>
          {faqs.map(([q, a]) => (
            <details key={q}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </section>

        <section className="closing" aria-labelledby="closing-title">
          <PixelTransition
            className="closing-pixels"
            firstContent={<img src="/assets/duck.png" alt="" />}
            secondContent={<img src="/assets/icon.png" alt="The MetalDuck app icon" />}
            gridSize={14}
            pixelColor="#dde1e7"
            pattern="dither"
            animationStepDuration={0.45}
            aspectRatio="100%"
          />
          <h2 id="closing-title">
            <ShinyText text="Give your Mac a smoother picture." color="#ffffff" shineColor="#9fc7ff" speed={3.2} />
          </h2>
          <DownloadButton label="Download MetalDuck 1.3.2" />
          <p className="fine">Requires an Apple silicon Mac with macOS 15 or later.</p>
        </section>
      </main>

      <footer className="footer">
        <span>MetalDuck is open source under the MIT license.</span>
        <a href={REPO}>GitHub</a>
        <a href={`${REPO}/releases`}>Releases</a>
        <a href={`${REPO}/issues`}>Report a problem</a>
        <a href="https://reactbits.dev">Animations from React Bits</a>
      </footer>
    </>
  );
}
