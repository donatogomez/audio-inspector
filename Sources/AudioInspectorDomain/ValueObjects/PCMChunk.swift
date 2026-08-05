/// One run of decoded audio: every channel's samples for the same span of frames.
///
/// ## Planar by construction
///
/// `channels[c]` is channel `c`'s samples, in file order, and every channel holds the same number of
/// them. There is no way to hand over an interleaved buffer and have it read as planar: an interleaved
/// run of *n* channels is one array of `n × frameCount` values, which this type can only accept as a
/// **single** channel of that length — a claim so obviously different from the truth that no consumer
/// could act on it by accident. The alternative, a flat array plus a stride, is exactly the shape that
/// makes the mistake invisible, and it is why this type does not offer one.
///
/// ## Values are copied, not borrowed
///
/// The samples are owned by the chunk. No pointer, no buffer view, no lifetime the consumer has to
/// respect: a `PCMChunk` handed to a callback stays valid on its own terms. That costs a copy per
/// chunk, and the cost is known rather than assumed — the spike's whole-file measurements were taken
/// through exactly this copy, and the time is dominated by decoding and the transform.
///
/// ## Non-finite samples cannot be represented
///
/// A chunk containing a `NaN` or an infinity does not exist. That is checked here, at the boundary,
/// rather than left to a later clamp: the spike measured a single `NaN` silently collapsing 184 cells
/// of a spectrogram to the floor, which would have made a corrupted region look like an absence of
/// energy. Values **outside `-1...1` are kept exactly as read** — those are real, and limiting them is
/// a concern of drawing, not of data.
public struct PCMChunk: Sendable, Equatable {
    /// The absolute frame the chunk's first sample sits at, counted from the start of the file.
    public let startFrame: Int
    /// One array per channel, all of the same length.
    public let channels: [[Float]]

    /// Frames covered by this chunk. Zero is representable: a decoder may legitimately hand over an
    /// empty run rather than special-casing the end of a file.
    public var frameCount: Int { channels.first?.count ?? 0 }

    public var channelCount: Int { channels.count }

    /// Fails when the parts do not describe a possible run of audio.
    ///
    /// Throwing rather than failable, unlike the other value types here, because every refusal has a
    /// distinct cause a caller can act on — a ragged chunk, a negative frame, a `NaN` — and collapsing
    /// them into one `nil` would discard the only information that makes the failure fixable.
    public init(startFrame: Int, channels: [[Float]]) throws(AudioDecodingError) {
        guard startFrame >= 0 else {
            throw AudioDecodingError(
                code: .invalidChunk,
                message: "A chunk cannot start at frame \(startFrame)."
            )
        }
        guard !channels.isEmpty else {
            throw AudioDecodingError(
                code: .invalidChunk,
                message: "A chunk must carry at least one channel."
            )
        }
        let frameCount = channels[0].count
        for (index, samples) in channels.enumerated() where samples.count != frameCount {
            throw AudioDecodingError(
                code: .invalidChunk,
                message: "Channel \(index) carries \(samples.count) frames where channel 0 carries \(frameCount)."
            )
        }
        for (index, samples) in channels.enumerated() {
            for (offset, sample) in samples.enumerated() where !sample.isFinite {
                throw AudioDecodingError(
                    code: .nonFiniteSample,
                    message: "Frame \(startFrame + offset) of channel \(index) is not a finite value."
                )
            }
        }

        self.startFrame = startFrame
        self.channels = channels
    }

    /// One channel's samples, or `nil` for a channel the chunk does not carry.
    public func samples(ofChannel index: Int) -> [Float]? {
        guard index >= 0, index < channels.count else { return nil }
        return channels[index]
    }

    /// Whether this chunk fits inside the stream it claims to come from.
    ///
    /// Checked by whoever owns both — the chunk cannot know which stream it belongs to, and a type that
    /// guessed would be wrong the first time a caller reused it.
    public func fits(_ stream: PCMStreamDescription) -> Bool {
        channels.count == stream.channelCount
            && startFrame + frameCount <= stream.frameCount
    }
}

/// What the consumer wants the decoder to do next.
///
/// Two cases, and no more: a decoder either keeps going or stops. There is deliberately no `.skip`,
/// no `.retry` and no error case — stopping early is not a failure, and giving a consumer a way to
/// report one through this channel would blur the difference between "I have seen enough" and
/// "something went wrong", which the caller's own error space already expresses.
public enum PCMChunkDisposition: Sendable, Equatable {
    /// Keep decoding.
    case `continue`
    /// Stop after this chunk. Not an error: the stream simply ends early, and the decoder returns
    /// normally.
    case stop
}
