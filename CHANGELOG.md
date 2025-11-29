# CHANGELOG

## 0.1.16
* Resolved [#38](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/38), standard libraries are included in the SBOM. Due to their special status inside of Julia, additional logic was needed to make them appear properly
* Resolved [#42](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/42), Inform user when package data is not in available registries

## v0.1.15
* Resolved [#40](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/40), Fails to generate SPDX in Julia 1.12 when artifacts are missing

## v0.1.14
* Merged [#39](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/pull/39), Add purl identifiers for packages

## v0.1.13
* Merged [#37](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/pull/37), Don't require custom registries to have a registry description

## v0.1.12
* Resolved [#34](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/34), [#9](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/9), Option to make the package server the download location instead of the GitHub repo
* Resolved [#33](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/33), adding source code for JLLs from Yggdrasil to the SBOM 

## v0.1.11
* Resolved [#18](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/18), Put a package's git tree hash in the Download Location
* Pulled out some trailing whitespace in information fields

## v0.1.10
Resolved [#7](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/7), Fill in Declared License field in SBOM
* Uses LicenseCheck.jl to scan packages and artifacts for license files and licenses embedded in source files.
* Also fill in package field License Info From Files.

## v0.1.9
Update SPDX package compatibility to v0.4.  This update enables the following:
* Updates the algorithm for computing the package verification code to a hopefully correct implementation.
* Allows the computation of artifact verification codes, since it is now able to ignore bad symbolic links.

## v0.1.8
Resolved [#2](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/2), Include artifacts in the SBOM

Resolved [#22](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/22), Document the version of Julia used to produce the SBOM

## v0.1.7
Resolved [#15](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/15), Avoid using Pkg internals

Resolved [#23](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/issues/23), Export SPDX when loading PkgToSoftwareBOM

Improvements to code coverage tests
