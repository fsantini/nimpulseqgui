import propertyedit
import nimpulseq
import nigui
import definitions
import std/strformat

proc formatFloat(v: float, increment: float): string =
    if increment < 0.01:
        return &"{v:.3f}"
    if increment < 0.1:
        return &"{v:.2f}"
    return &"{v:.1f}"

proc createPropertyContainer(propertyName: string, opts: Opts, prot: MRProtocolRef, validateProc: ProcValidateProtocol, parentWindow: Window): LayoutContainer =
    let prop = prot[propertyName]

    var propContainer = newLayoutContainer(Layout_Horizontal)

    # edit button. Only added if it's not a description
    var editButton = newButton("Edit")
    

    # also the name of the property is only added if it's not a description
    var labelName = newLabel(propertyName)
    labelName.fontBold = true

    if prop.pType != ptDescription:
        propContainer.add(editButton)
        propContainer.add(labelName)

    var labelValue = newLabel()

    proc updateValue() =
        var valueString: string
        let prop = prot[propertyName]
        case prop.pType
        of ptDescription: valueString = prop.description
        of ptInt: valueString = prop.intVal.repr & " " & prop.unit
        of ptFloat: valueString = formatFloat(prop.floatVal, prop.floatIncr) & " " & prop.unit
        of ptBool: valueString = if prop.boolVal: "True" else: "False"
        of ptStringList: valueString = prop.stringVal
        labelValue.text = valueString

    updateValue()

    proc editPressCallback(click: ClickEvent) =
        var win = showPropertyEditor(opts, prot, propertyName, validateProc)
        win.onDispose = proc(e: WindowDisposeEvent) = updateValue()
        win.showModal(parentWindow)

    editButton.onClick = editPressCallback

    propContainer.add(labelValue)
    return propContainer



proc sequenceGUI*(opts: Opts, prot: MRProtocolRef, validateProc: ProcValidateProtocol, makeSequence: ProcMakeSequence): Window {. discardable .} =
    var window = newWindow("Nimpulseq GUI")
    window.width = 800.scaleToDpi
    window.height = 600.scaleToDpi
    var mainContainer = newLayoutContainer(Layout_Vertical)
    for propName in prot.keys:
        mainContainer.add(createPropertyContainer(propName, opts, prot, validateProc, window))
    window.add(mainContainer)
    return window

when isMainModule:
    var validateTest: ProcValidateProtocol = proc (opts: Opts, protocol: MRProtocolRef): bool =
        var prop = protocol["TE"].floatVal
        if prop < 10 or prop > 100:
            return false
        if protocol["Bool"].boolVal == false:
            return false
        if protocol["String"].stringVal == "Hallo":
            return false
        return true


    var teProperty = ProtocolProperty(pType: ptFloat, floatMin: 0, floatMax: 1000, floatVal: 50, floatIncr: 1, validateStrategy: pvDoSearch, changed: false, unit: "ms")
    var intProperty = ProtocolProperty(pType: ptInt, intMin: 20, intMax: 100, intVal: 50, intIncr: 1, validateStrategy: pvNoSearch, changed: false, unit: "u")
    var boolProperty = ProtocolProperty(pType: ptBool, boolVal: true, validateStrategy: pvNoSearch, changed: false, unit: "")
    var stringProperty = ProtocolProperty(pType: ptStringList, stringVal: "Hello", stringList: @["Ciao", "Hello", "Hallo", "Geia"], validateStrategy: pvDoSearch, changed: false, unit: "")
    var prot = MRProtocolRef()
    var opts = newOpts()
    prot["TE"] = teProperty
    prot["Int"] = intProperty
    prot["Bool"] = boolProperty
    prot["String"] = stringProperty
    
    app.init()
    var window = sequenceGUI(opts, prot, validateTest, nil)
    window.show()
    app.run()