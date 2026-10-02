# VibePollo host compatibility audit

Host examined: Nonary/Vibepollo `8a8c4b03a280ab9f567beb380110abb80f5220b8`.
Client examined: Koloses/aurora-qt `2c574a9e79da5b3fa95bab90ffd3d322f5d63ac0`.

The host's src/pyrowave_protocol.h explicitly matches the Aurora/Solarflare
capability bits (0x00800000 through 0x04000000) and bitStreamFormat=3. Aurora's
common-c sends pyrowaveAdaptiveFec and pyrowaveAdaptiveBitrate. The host selects
record framing on the presence of the former, including when its value is zero.
Both parsers use 8-byte sequence/block headers and 0xFFFFFFFF padding records.
Thus negotiation and framing match at source level.

The host vendors upstream PyroWave at `186f0393b77f7755953b5ecde994bb1cec2e4155`,
whereas Aurora vendors a WiVRn derivative without a corresponding bitstream ID.
The host's docs/pyrowave-protocol.md explicitly says Aurora negotiates PyroWave
but frames decode only if that older decoder matches bitstream `186f0393`.
Matching header fields and framing is insufficient to prove wavelet decoding
interoperability. No VibePollo streaming session has been tested here.

Test the exact VibePollo release your friend will use, force PyroWave in Aurora,
and retain host/client logs and a moving-image playback recording. Treat VibePollo
PyroWave compatibility as UNVERIFIED until that test passes. The original Aurora
codec and Solarflare protocol have been retained; no codec substitution was made.

Sources:
* https://github.com/Nonary/Vibepollo/blob/8a8c4b03a280ab9f567beb380110abb80f5220b8/src/pyrowave_protocol.h
* https://github.com/Nonary/Vibepollo/blob/8a8c4b03a280ab9f567beb380110abb80f5220b8/docs/pyrowave-protocol.md
