import std/sequtils
export sequtils
import std/tables
export tables
import nimpulseq

type
  PropertyType* = enum
    ptInt,
    ptFloat,
    ptBool,
    ptStringList,
    ptDescription
  PropertyValidate* = enum
    pvDoSearch, # This does a binary search for numerical values, and a full search for non-numerical
    pvNoSearch
  ProtocolProperty* = object
    case pType*: PropertyType
    of ptInt: 
      intVal*: int
      intMin*: int
      intMax*: int
      intIncr*: int
    of ptFloat:
      floatVal*: float
      floatMin*: float
      floatMax*: float
      floatIncr*: float
    of ptBool:
      boolVal*: bool
    of ptStringList: 
      stringVal*: string
      stringList*: seq[string]
    of ptDescription:
      description*: string
    unit*: string
    validateStrategy*: PropertyValidate
    changed*: bool
  MRProtocolRef* = OrderedTableRef[string, ProtocolProperty] # this is a reference to an orderedtable. It exists on the heap and is mutable
  ProcValidateProtocol* = proc(opts: Opts, protocol: MRProtocolRef): bool {. closure .}
  ProcMakeSequence* = proc(opts: Opts, protocol: MRProtocolRef): Sequence {. closure .}
  ProcGetDefaultProtocol* = proc(opts: Opts): MRProtocolRef {. closure .}

# this is used to make a local copy of a protocol, since by itself a protocol is a reference
proc copy*(src: MRProtocolRef): MRProtocolRef =
    result = new MRProtocolRef
    result[] = src[]
