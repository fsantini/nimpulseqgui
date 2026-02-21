nimpulseqgui
============

A Nim framework for building GUI and CLI applications that define, validate,
and write `Pulseq <https://pulseq.github.io/>`_ ``.seq`` files.

Users extend the framework by providing three callbacks and calling
``makeSequenceExe(getDefaultProtocol, validateProtocol, makeSequence)`` as
their application entry point.

.. toctree::
   :maxdepth: 2
   :caption: Contents

   quickstart
   api/index
