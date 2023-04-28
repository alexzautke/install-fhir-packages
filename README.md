## install-fhir-packages

Upload the conformance resources bundled in a FHIR package to any FHIR server using Firely.Terminal tool (https://simplifier.net/downloads/firely-terminal).

## Quickstart

Simply run ``./install-fhir-packages.sh`` within a working directory. 
All FHIR packages will be installed locally in this folder before being uploaded to a specified FHIR server.

```
FHIR package name: de.basisprofil.r4
FHIR package version (latest): <enter>
Upload package to FHIR server: https://server.fire.ly/administration/r4

...

```

## Requirements

The script will automatically check on start-up if all of the following requirements are installed:

- jq (https://stedolan.github.io/jq/)
- fhir (firely.terminal)

