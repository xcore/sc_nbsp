NBSP SOFTWARE COMPONENT
.......................

:Stable release:  unreleased
:Latest release:  0.1.0
:Status:  beta
:Maintainer:  errsu
:Description:  NBSP - a protocol for convenient asynchronous inter-core communication


Key Features
============

* non-blocking: sender and receiver are never blocked waiting for the peer or the channel
* bi-directional: totally symmetric, both peers may send and receive at the same time
* small-package: fixed package size of 32 bits, handy for MIDI messages, for example
* flexible: low network load, transparent across tiles, synchronous and uni-directional modes

Firmware Overview
=================

* module_nbsp: the protocol implementation
* app_nbsp_startkit_demo: makes the message exchange visible on the STARTKIT
* app_nbsp_multiplayer: 16 players are communicating in both directions over 32 channels
* app_nbsp_performance: measures throughput of NBSP on a single channel

Documentation
=============

See nbsp.h for the API and how to use it, and nbsp.xc for details of the protocol.

Known Issues
============

None at the moment.

Support
=======

The maintainer makes no promises to support this component. Comments and questions are welcome, though.
