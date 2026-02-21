## nimpulseqgui — GUI/CLI framework for building Pulseq sequence applications.
##
## This module re-exports the complete public API:
##
## - ``definitions`` — core types (``ProtocolProperty``, ``MRProtocolRef``, callback aliases)
##   and property constructors (``newFloatProperty``, ``newIntProperty``, etc.)
## - ``sequenceexe`` — ``makeSequenceExe``, the single entry point for user applications.
##
## Users call ``makeSequenceExe(getDefaultProtocol, validateProtocol, makeSequence)``
## as the body of their ``main`` after importing this module.

import nimpulseqgui/definitions
export definitions

import nimpulseqgui/sequenceexe
export sequenceexe

