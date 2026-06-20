# Expensive CALayer Hosting Demo (Option A)

A minimal macOS SwiftUI app showing how to host an **expensive CALayer-based
rendering system out of SwiftUI** so that SwiftUI's view-identity churn never
destroys (and rebuilds) the costly object.

## The idea ("Option A")

- The expensive thing is a `CALayer` tree + renderer (`ExpensiveRenderer`).
- It is owned by an **external pool** (`RendererPool`) keyed by a stable token
  *you* mint — not by SwiftUI's identity.
- SwiftUI owns only `LayerHostView`, a cheap, disposable `NSView`. On
  `makeNSView` it **reparents** the shared root layer into itself; on
  `dismantleNSView` it just **detaches** the layer (the pool keeps it alive).
- Moving a `CALayer` between superlayers **preserves its backing store** — Core
  Animation does not re-render on reparent — so teardown becomes ~free.

## Run

```sh
swift run
```

(The window may open behind your terminal the first time — the app forces
itself to the foreground, but you can also Cmd-Tab to it.)

## What to try

1. Leave **"Use pooled renderer"** ON. Click **"Force SwiftUI teardown"**
   repeatedly.
   - `Renderers built` **stays at 1**.
   - The spinner keeps spinning and the tick counter keeps climbing — the live
     layer state survived the teardown.
   - No freeze.
2. Turn the toggle **OFF** (naive baseline). Click **"Force SwiftUI teardown"**.
   - `Renderers built` **climbs every time**.
   - The window **freezes ~1s** on each rebuild (the simulated build cost).
   - The spinner and tick counter **reset** — the old work was thrown away.
3. Watch `heartbeat` increment every second the whole time: that proves cheap
   struct re-evaluation does **not** cause `makeNSView`/`dismantleNSView`.

## Files

| File | Role |
|------|------|
| `ExpensiveRenderer.swift` | The heavy CALayer system (artificial cost + live state). |
| `RendererPool.swift` | External owner of renderers, keyed by stable id. |
| `LayerHostView.swift` | Disposable host `NSView` + the pooled & naive representables. |
| `ContentView.swift` | Demo UI + metrics. |
| `Metrics.swift` | Observable counters. |
| `App.swift` | App entry + foreground activation. |

## Notes / next steps

- A `CALayer` has exactly one superlayer, so this hosts the renderer in one
  place at a time. To show the same content in multiple places simultaneously,
  use mirroring (`CAReplicatorLayer` or a portal layer) instead of moving it.
- The `evict(id:)` hook on the pool is where you'd add real memory management
  (e.g. an LRU cap) once renderers are numerous.
