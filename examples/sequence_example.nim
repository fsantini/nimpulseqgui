import nimpulseqgui
import std/math

proc greDefaultProtocol(opts: Opts): MRProtocolRef =
    var prot = newProtocol()
    prot["Description"] = newDescriptionProperty("This is an example GRE sequence")
    prot["D2"] = newDescriptionProperty("Resolution")
    prot["FOV"] = newIntProperty(100, 1, 500, 1, pvDoSearch, "mm")
    prot["Slice Thickness"] = newIntProperty(5, 1, 20, 1, pvDoSearch, "mm")
    prot["Matrix Size"] = newIntProperty(64, 32, 512, 32, pvDoSearch)
    prot["D3"] = newDescriptionProperty("Timing")
    prot["TE"] = newFloatProperty(5.0, 1.0, 100.0, 0.1, pvDoSearch, "ms")
    prot["TR"] = newFloatProperty(10.0, 1.0, 1000.0, 0.1, pvDoSearch, "ms")
    prot["RF Spoiling"] = newBoolProperty(true, pvNoSearch)
    prot["Flip Angle"] = newFloatProperty(10.0, 1.0, 90.0, 1.0, pvDoSearch, "degrees")
    return prot

# template to assign default values, to avoid writing it multiple times.
template defaultValues() {. dirty .} =
    let fov {. used .} = float64(prot["FOV"].intVal) * 1e-3 # convert to meters
    let Nx {. used .} = prot["Matrix Size"].intVal
    let Ny {. used .} = Nx
    let alpha {. used .} = prot["Flip Angle"].floatVal # flip angle in degrees
    let sliceThickness = float64(prot["Slice Thickness"].intVal) * 1e-3
    let nSlices {. used .} = 1
    let TE {. used .} = prot["TE"].floatVal * 1e-3
    let TR {. used .} = prot["TR"].floatVal * 1e-3
    let rfSpoilingInc {. used .} = if prot["RF Spoiling"].boolVal: 117.0 else: 0.0
    let roDuration {. used .} = 3.2e-3


# this function validates the timing of the protocol, but does not actually make the sequence
proc validateProtocol(opts: Opts, prot: MRProtocolRef): bool =
    defaultValues()
    let system = opts
    var seqObj = newSequence(system)

    # ======
    # CREATE EVENTS
    # ======
    var (_, gz, _) = makeSincPulse(
        flipAngle = alpha * PI / 180.0,
        duration = 3e-3,
        sliceThickness = sliceThickness,
        apodization = 0.5,
        timeBwProduct = 4.0,
        system = system,
        returnGz = true,
        delay = system.rfDeadTime,
        use = "excitation",
    )

    let deltaK = 1.0 / fov
    let gx = makeTrapezoid(channel = "x", flatArea = float64(Nx) * deltaK, flatTime = roDuration, system = system)
    let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0, duration = 1e-3, system = system)

    let phaseAreas_min = -(float64(Ny) / 2.0) * deltaK
    let phaseAreas_max = (float64(Ny) / 2.0) * deltaK
    let phaseArea = max(abs(phaseAreas_min), abs(phaseAreas_max))

    let gyPre = makeTrapezoid(channel = "y", area = phaseArea, system = system)

    if calcDuration(gyPre) > calcDuration(gxPre):
        # Validation failed: Phase encoding gradient duration is too long for the specified parameters.
        return false 
    
    # Gradient spoiling
    let gxSpoil = makeTrapezoid(channel = "x", area = 2.0 * float64(Nx) * deltaK, system = system)
    let gzSpoil = makeTrapezoid(channel = "z", area = 4.0 / sliceThickness, system = system)

    # Calculate timing
    let delayTE = ceil(
        (TE - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 -
        calcDuration(gx) / 2.0) / seqObj.gradRasterTime
    ) * seqObj.gradRasterTime

    let delayTR = ceil(
        (TR - calcDuration(gz) - calcDuration(gxPre) - calcDuration(gx) - delayTE) /
        seqObj.gradRasterTime
    ) * seqObj.gradRasterTime

    if delayTE < 0.0:
        # Validation failed: TE is too short for the specified parameters.
        return false
    
    if delayTR < calcDuration(gxSpoil, gzSpoil):
        # Validation failed: TR is too short for the specified parameters.
        return false

    # Validation ok
    return true
    

# this function actually constructs the sequence.
proc writeGreLabelSeq(opts: Opts, prot: MRProtocolRef): Sequence =
    # ======
    # SETUP
    # ======
    defaultValues()

    let system = opts

    var seqObj = newSequence(system)

    # ======
    # CREATE EVENTS
    # ======
    var (rf, gz, _) = makeSincPulse(
        flipAngle = alpha * PI / 180.0,
        duration = 3e-3,
        sliceThickness = sliceThickness,
        apodization = 0.5,
        timeBwProduct = 4.0,
        system = system,
        returnGz = true,
        delay = system.rfDeadTime,
        use = "excitation",
    )

    let deltaK = 1.0 / fov
    let gx = makeTrapezoid(channel = "x", flatArea = float64(Nx) * deltaK, flatTime = roDuration, system = system)
    var adc = makeAdc(numSamples = Nx, duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)
    let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0, duration = 1e-3, system = system)
    let gzReph = makeTrapezoid(channel = "z", area = -gz.trapArea / 2.0, duration = 1e-3, system = system)

    var phaseAreas = newSeq[float64](Ny)
    for i in 0 ..< Ny:
        phaseAreas[i] = -(float64(i) - float64(Ny) / 2.0) * deltaK

    

    # Gradient spoiling
    let gxSpoil = makeTrapezoid(channel = "x", area = 2.0 * float64(Nx) * deltaK, system = system)
    let gzSpoil = makeTrapezoid(channel = "z", area = 4.0 / sliceThickness, system = system)

    # Calculate timing
    let delayTE = ceil(
        (TE - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 -
        calcDuration(gx) / 2.0) / seqObj.gradRasterTime
    ) * seqObj.gradRasterTime

    let delayTR = ceil(
        (TR - calcDuration(gz) - calcDuration(gxPre) - calcDuration(gx) - delayTE) /
        seqObj.gradRasterTime
    ) * seqObj.gradRasterTime

    assert delayTE >= 0
    assert delayTR >= calcDuration(gxSpoil, gzSpoil)

    var rfPhase = 0.0
    var rfInc = 0.0

    seqObj.addBlock(makeLabel("SET", "REV", 1))

    # ======
    # CONSTRUCT SEQUENCE
    # ======
    for s in 0 ..< nSlices:
        rf.rfFreqOffset = gz.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
        for i in 0 ..< Ny:
            rf.rfPhaseOffset = rfPhase / 180.0 * PI
            adc.adcPhaseOffset = rfPhase / 180.0 * PI
            rfInc = (rfInc + rfSpoilingInc) mod 360.0
            rfPhase = (rfPhase + rfInc) mod 360.0

            seqObj.addBlock(rf, gz)
            var gyPre = makeTrapezoid(
                channel = "y",
                area = phaseAreas[i],
                duration = calcDuration(gxPre),
                system = system,
            )
            seqObj.addBlock(gxPre, gyPre, gzReph)
            seqObj.addBlock(makeDelay(delayTE))
            seqObj.addBlock(gx, adc)
            gyPre.trapAmplitude = -gyPre.trapAmplitude
            var spoilBlockContents = @[makeDelay(delayTR), gxSpoil, gyPre, gzSpoil]
            if i != Ny - 1:
                spoilBlockContents.add(makeLabel("INC", "LIN", 1))
            else:
                spoilBlockContents.add(makeLabel("SET", "LIN", 0))
                spoilBlockContents.add(makeLabel("INC", "SLC", 1))
            seqObj.addBlock(spoilBlockContents)

    let (ok, errorReport) = seqObj.checkTiming()
    if ok:
        echo "Timing check passed successfully"
    else:
        echo "Timing check failed. Error listing follows:"
        for e in errorReport:
            echo e
        raise newException(ValueError, "Timing check failed. See error report for details.")

    seqObj.setDefinition("Name", "gre_example")
    seqObj.setDefinition("FOV", @[fov, fov, sliceThickness])

    return seqObj

makeSequenceExe(greDefaultProtocol, validateProtocol, writeGreLabelSeq, "Simple GRE Example in NimPulseSeqGUI")