# nimpulseqgui

nimpulseqgui provides a small GUI and helper API to define protocol parameters for Pulseq-compatible sequences, validate them, and write Pulseq sequences.

**Highlights**
- Command-line tool with optional GUI to edit protocol parameters and write sequences.
- Programmatic API to build a default protocol (`MRProtocolRef`) using typed property constructors.
- Simple extensibility: supply a `ProcValidateProtocol` and `ProcMakeSequence` to integrate sequences.

Programmatic usage
- Provide three callbacks and call `makeSequenceExe(getDefaultProtocol, validateProtocol, makeSequence)` from your `main` to wire the UI/CLI to your sequence logic.

Library usage
- This project is intended as a library to help you write your own Pulseq sequences — it is not meant to be used as a turnkey, standalone sequence distribution. To create a sequence application you should:
	- Implement a function returning a default protocol with signature `proc(opts: Opts): MRProtocolRef` (the `ProcGetDefaultProtocol`-style function).
	- Implement a validation function with signature `proc(opts: Opts, prot: MRProtocolRef): bool` (`ProcValidateProtocol`).
	- Implement a sequence builder with signature `proc(opts: Opts, prot: MRProtocolRef): Sequence` (`ProcMakeSequence`).
	- Compile an executable that calls `makeSequenceExe` with these three functions. Distribute the resulting binary (or the source) for others to run — this keeps your sequence logic packaged separately from the UI helpers in this repo.


Example (see `src/sequence_example.nim`):
- Implement `proc greDefaultProtocol(opts: Opts): MRProtocolRef` to construct a default protocol.
- Use the helper constructors (below) to populate `MRProtocolRef`:

	prot = newProtocol()
	prot["Description"] = newDescriptionProperty("This is an example GRE sequence")
	prot["TE"] = newFloatProperty(5.0, 1.0, 100.0, 0.1, pvDoSearch, "ms")
	prot["FOV"] = newIntProperty(100, 1, 500, 1, pvDoSearch, "mm")
	prot["RF Spoiling"] = newBoolProperty(true)

- Implement `proc validateProtocol(opts: Opts, prot: MRProtocolRef): bool` to validate parameters.
- Implement `proc writeGreLabelSeq(opts: Opts, prot: MRProtocolRef): Sequence` to construct and return the Pulseq `Sequence`.
- Call `makeSequenceExe(greDefaultProtocol, validateProtocol, writeGreLabelSeq)` in your executable entrypoint.

Protocol API (defined in `src/nimpulseqgui/definitions.nim`)
- `type MRProtocolRef = OrderedTableRef[string, ProtocolProperty]` — a mutable reference-table mapping names to properties.
- `newProtocol(): MRProtocolRef` — allocates an empty protocol table.
- Property constructors (exported helpers):
	- `newFloatProperty(val, min, max, incr: float; validate: PropertyValidate = pvNoSearch; unit: string = ""): ProtocolProperty`
	- `newIntProperty(val, min, max, incr: int; validate: PropertyValidate = pvNoSearch; unit: string = ""): ProtocolProperty`
	- `newBoolProperty(val: bool; validate: PropertyValidate = pvNoSearch): ProtocolProperty`
	- `newStringListProperty(val: string; list: seq[string]; validate: PropertyValidate = pvNoSearch): ProtocolProperty`
	- `newDescriptionProperty(desc: string): ProtocolProperty`

- `ProcValidateProtocol = proc(opts: Opts, protocol: MRProtocolRef): bool` — signature for validation callbacks.
- `ProcMakeSequence = proc(opts: Opts, protocol: MRProtocolRef): Sequence` — signature for sequence construction callbacks.

License
- See the repository `LICENSE` for licensing details.


