# nfp-common/firmware

 Copyright (c) 2016 Netronome Systems, Inc.
 All rights reserved.

## Description

This directory contains source, library and build directories for NFP
firmware.

## Makefiles

### Makefile

The makefile contains the basic variable settings for firmware builds
and it includes the make templates and then the application makefile

### Makefile.templates

This file contains standard templates for simplifying firmware builds
through assembler and micro-c compilation, and linking.

### Makefile.apps

This file contains includes to build specific applications from their
Makefile subdirectories.

## 'lib' subdirectory

The lib subdirectory contains firmware libraries.

## 'app' subdirectory

The app subdirectory contains firmware source code that may utilize
libraries, and which builds into firmware objects which are combined
into an 'nffw' firmware build.

Hence each microengine code load has a toplevel firmware source code
file in this directory; it may use other firmware source code files in
this directory as well as libraries.

## extern

Contains external components that are required to build projects.

## build

The build subdirectory contains intermediate build files for firmware
builds.

## nffw

The nffw subdirectory contains the final firmware objects that can be
loaded onto the NFP.
