import std/sequtils
export sequtils
import std/tables
import nimpulseq

type
  PropertyType* = enum
    ptInt,
    ptFloat,
    ptBool,
    ptStringList
  PropertyValidate* = enum
    pvBinarySearch,
    pvFullSearch,
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
    validateStrategy*: PropertyValidate
    changed*: bool
  MRProtocol* = OrderedTable[string, ProtocolProperty]
  ProcValidateProtocol* = proc(protocol: MRProtocol): bool
  ProcMakeSequence* = proc(protocol: MRProtocol): Sequence
  ProcGetDefaultProtocol* = proc(): MRProtocol


