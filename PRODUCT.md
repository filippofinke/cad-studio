# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

The product is a native macOS app (SwiftUI + AppKit, macOS 15+). The landing page in `site/` is a separate `web` surface.

## Stack

App: Swift 6, SwiftUI, RealityKit, hand-written Xcode project. Landing page: static HTML/CSS/JS in `site/`, deployed to GitHub Pages by a GitHub Actions workflow.

## Users

Makers, tinkerers and 3D-printing hobbyists on a Mac who need functional parts (hooks, brackets, latches, enclosures) but don't want to learn a CAD program. They already use, or are willing to install, Claude Code.

## Product Purpose

You describe a part in chat; CAD Studio runs the Claude Code installed on your Mac, which writes and runs a parametric build123d `model.py` and returns a 3D model, ISO technical drawings and files ready for the slicer. Success: a printable part from a sentence, editable afterwards through parameters or more chat.

## Positioning

Real parametric CAD code (build123d `model.py`) written and executed locally by the user's own Claude Code, not a mesh generator: every dimension is a named constant you can slide, every change is a version you can go back to, and the outputs are engineering files (STEP, 3MF, ISO drawings), not just a pretty mesh.

## Operating Context

A Mac on the workbench next to a 3D printer. The user types or attaches a sketch, watches the agent work (live tool rows, code streaming, thinking), then checks the model in 3D, measures, sections, compares versions, adjusts parameters and opens the print plate in their slicer.

## Capabilities and Constraints

- Chat with an agent that writes and fixes parametric build123d scripts; live progress (tool calls, streaming code, thinking tokens, elapsed time).
- 3D viewer: orbit/zoom/pan, grid, wireframe, multi-color 3MF parts, measure, section, compare versions.
- Multi-part models: assembled, exploded and print-plate views; hide parts or keep them attached.
- Physics animation of mechanisms (masses, springs, friction, collision checks) played in the app.
- ISO first-angle drawings: assembly sheet with parts list plus one sheet per part, multi-page PDF.
- Floating parameter sliders that rebuild without calling Claude.
- Version history with chat and agent context restored.
- Export STEP, 3MF, STL, PDF and `model.py` as a ZIP; print plate opens in the slicer.
- Printer-aware rules (FDM, multi-material, resin, SLS), units mm/cm/m/in; UI in English, Italian, German, French.
- Requires macOS 15+, Claude Code signed in, uv or Python 3.10–3.13. Uses the user's Claude Code plan. Not notarized (Gatekeeper workaround needed).
- Free, MIT licensed, open source. No pricing, no accounts, no cloud backend of its own.

## Brand Commitments

Name "CAD Studio". Blueprint-cube app icon (`.github/logo.png`). Built by Filippo Finke (filippofinke.ch). Not affiliated with Anthropic; never use Anthropic or Claude branding as its own.

## Evidence on Hand

- Screenshots: `.github/screenshots/` (setup, new-project, prompt, agent, model, parameters, measure, section, version-2, compare, restore, layout-right, layout-bottom, light, settings).
- Demo: `.github/demo.gif`, narrated `.github/demo.mp4` (under-desk headphone hook with two M4 screws).
- Real releases on GitHub: https://github.com/filippofinke/cad-studio/releases/latest (`CADStudio.dmg`).
- No testimonials, user counts, press, benchmarks or download numbers exist; never invent them.

## Product Principles

- Engineering truth over spectacle: real parametric code, real dimensions, real files.
- The user stays in control: every number editable, every step visible, every version recoverable.
- Local and theirs: runs on their Mac with their own Claude Code; nothing is uploaded by the app.
- From sentence to printer: the job ends at a part on the print bed, not at a render.
