<p align="center">
  <img src="assets/images/logo.png" width="96" alt="KIVO logo" />
</p>

<h1 align="center">KIVO</h1>
<p align="center"><strong>Compress videos, images, PDFs, and structured files — entirely offline</strong></p>
<p align="center">
  <img src="https://img.shields.io/badge/version-3.1.0-blue" alt="version" />
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-informational" alt="platforms" />
  <img src="https://img.shields.io/badge/100%25%20offline-no%20cloud-success" alt="offline" />
</p>

---

## What is KIVO?

KIVO compresses files directly on your device — **no internet connection, no server, no file uploads**.

Your files never leave your machine. Processing uses FFmpeg (video), native platform APIs (images), and pure-Dart implementations (PDFs, JSON, XML, YAML) — all bundled inside the app.

---

## Supported formats

| Type            | Input formats                          | Output   |
|-----------------|----------------------------------------|----------|
| Video           | MP4, MOV, M4V, AVI, MKV, WEBM         | MP4      |
| Image           | JPG, PNG, WEBP, HEIC, HEIF            | JPG      |
| PDF             | PDF                                    | PDF      |
| JSON            | JSON                                   | JSON     |
| XML             | XML                                    | XML      |
| YAML            | YAML, YML                              | YAML     |

---

## How to use

1. **Add files** — tap _Select File_ or drag and drop onto the app (desktop)
2. **Compress** — tap _Compress_ and follow the progress bar
3. **Save** — choose where to save when the compression finishes
4. **Open** — tap any completed item in the queue to open the file directly

No sign-up, no configuration, no internet required.

---

## Compression examples

Results vary by content, but here are real-world numbers:

### Video
| Original       | Compressed | Reduction  |
|----------------|------------|------------|
| 68.8 MB (MOV)  | 39.9 MB    | **−42%**   |
| 120 MB (MP4)   | ~55 MB     | **~−54%**  |

> Uses FFmpeg with HEVC/H.264 and adaptive bitrate. Falls back to libx264 software encoding for maximum compatibility (including `.mov` files with GBR colorspace).

### Image
| Original       | Compressed | Reduction  |
|----------------|------------|------------|
| 4.2 MB (PNG)   | 1.1 MB     | **−74%**   |
| 800 KB (JPG)   | 310 KB     | **−61%**   |

> Re-encoded as JPEG with quality 72, metadata stripped. Uses platform APIs on mobile (HEIC support) and the Dart `image` package on desktop.

### PDF
| Original       | Compressed | Reduction  |
|----------------|------------|------------|
| 7.6 MB (PDF)   | 3.2 MB     | **−58%**   |
| 2.1 MB (PDF)   | 900 KB     | **−57%**   |

> Pages are rasterized and re-encoded as JPEG. Useful for scan-heavy PDFs.

### JSON / XML / YAML
Whitespace, comments, and blank lines are removed, producing the smallest valid representation of the original content — structure and data are always preserved.

---

## Privacy

- **100% offline** — the app never accesses the internet
- **No account required** — zero personal data collected
- **Local processing only** — files never leave your device
- **Open source** — the full source code is available for inspection

Ideal for confidential documents, personal videos, or any file you would rather not send to a cloud service.

---

## Platform support

| Platform | Status                              |
|----------|-------------------------------------|
| macOS    | ✅ Supported (Apple Silicon + Intel via Rosetta) |
| Windows  | ✅ Supported                         |
| Linux    | ✅ Supported                         |
| Android  | ✅ Supported                         |
| iOS      | ✅ Supported (physical device for video) |

---

## Download

Visit the [releases page](https://github.com/eltonccdantas/kivo/releases) to download the latest build for your platform.

---

## Tech stack

| Component       | Technology                                    |
|-----------------|-----------------------------------------------|
| UI framework    | Flutter (Material 3, dark theme)              |
| Video           | FFmpeg (bundled binary + `ffmpeg_kit` on mobile) |
| Image           | `flutter_image_compress` (mobile), Dart `image` (desktop) |
| PDF             | `printing` + `pdf` packages                  |
| JSON            | `dart:convert`                                |
| XML             | `xml` package                                 |
| YAML            | Pure Dart line parser                         |

---

<p align="center">
  eltondantas.com &nbsp;=)
</p>
