# Molecular Renderer

Scriptable application for running OpenMM simulations and visualizing at high framerates. Provides up to 120 Hz uninterrupted playback with real-time ray tracing.

TODO (performance):
- Perform decompression, refitting, rendering, and upscaling for 4 frames concurrently.
- Compact the acceleration structure every 4 frames.
- Delay presentation by another 4 frames (16 MB) to absorb stream interruptions.
- Use Metal lossless compression to reduce bandwidth of delayed frames.
- Store previous frame's transform data to re-project intersection position onto screen, generate screen-space motion vector.

TODO (user interface):
- Modular mechanism to plug in different scripts, so I can save my research in a separate repo.
- Video exporting tool, demo video of a rod-logic mechanical computer.
- Basic interactivity with the visualization.
- Display OpenMM ps/s, ns/day and rendering ps/s.
- Serialization format to auto-save an in-progress simulation, halt progress at specified GB limit.
- Interactive mechanism to adjust aspect ratio while maintaining 1 million pixels.
- Support replaying at integer multiples of the sample rate.

## Requirements

Dependencies:
- macOS Ventura, Apple M1 chip
- Xcode 14 installed
- OpenMM 8.0 with the [Metal plugin](https://github.com/philipturner/openmm-metal) installed

Memory:
- At least 8 GB of RAM - this application will cache 4 GB of compressed data in memory
- Before compression: 140 MB data per second of playback per 100,000 atoms
- Solid-state drive or high-bandwidth HDD, over 10 GB of free disk space

Display:
- 512x512 -> 1024x1024 upscaled with MetalFX temporal upscaling
- Need monitor with at least 1024x1024 pixels
- Only 60 Hz and 120 Hz supported
- Window aspect ratio is adjustable, but will resize to stay at 1 million pixels

## Technical Details

This application currently requires an Apple M1 chip running Metal 3. It is optimized for the author's personal machine (M1 Max), and samples the OpenMM simulation 120 times per second\*. The platform restriction makes it easier for the author to develop, but it can be ported to other devices. For example, MetalFX spatial upscaling would let it run on Intel Macs. One could also port it to Windows through Vulkan and FidelityFX.

> \*When targeting a 60 Hz display or exporting 24 Hz video, the frames are simply downsampled.

Before serialization, geometry data packs into an efficient format - three `float` numbers per atom, with a stride of 12 B. The velocity is computed using positions between frame timestamps, rather than the actual atomic velocities. This is more appropriate for MetalFX temporal upscaling and removes the need to store velocity. Finally, the geometry data is archived using the [LZBITMAP](https://developer.apple.com/documentation/compression/compression_lzbitmap) lossless compression algorithm.

Asuming 4 fs time step @ 120 Hz, playback speed must be a multiple of 0.48 ps/s. Replaying at exactly 0.48 ps/s would cause a significant bottleneck; OpenMM would halt the GPU command stream every step. To prevent this bottleneck, try to replay at something over 10 ps/s. Also check how quickly OpenMM is simulating, to gauge how long you'll wait before visualizing. OpenMM would generate 1.2 ps/s of data when simulating 100 ns/day, something achievable with the M1 Max and ~100,000 atoms.

## References

https://forums.macrumors.com/threads/observations-discussion-on-apple-silicon-graphics-performance-with-metalfx-upscaling.2368474/

https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5063251/
