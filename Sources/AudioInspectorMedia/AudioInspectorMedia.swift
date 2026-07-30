/// Probing and decoding adapters — the only module that may import AVFoundation/AudioToolbox or
/// spawn `Process` (FFmpeg/FFprobe). Depends only on the domain.
///
/// Empty at the scaffolding stage; native probing/decoding arrives with the first vertical slice.
public enum AudioInspectorMedia {}
