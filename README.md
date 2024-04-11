# PkgToSoftwareBOM.jl

[![GitHub Actions](https://github.com/SamuraiAku/PkgToSoftwareBOM.jl/workflows/CI/badge.svg)](https://github.com/SamuraiAku/SPDX.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/SamuraiAku/PkgToSoftwareBOM.jl/graph/badge.svg?token=A1GLEJG7LW)](https://codecov.io/gh/SamuraiAku/PkgToSoftwareBOM.jl)
[![PkgToSoftwareBOM Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/PkgToSoftwareBOM)](https://pkgs.genieframework.com?packages=PkgToSoftwareBOM)

This package produces a Software Bill of Materials (SBOM) describing your Julia environment. At this time, the SBOM produced is in the ([SPDX](https://github.com/SamuraiAku/SPDX.jl)) format.  Contributions to support other SBOM formats are welcome.

I created PkgToSoftwareBOM.jl to help the Julia ecosystem get prepared for the emerging future of software supply chain security. If we want to see Julia adoption to continue to grow, then we need to be able to easily create SBOMs to supply to the organizations using Julia packages.

PkgToSoftwareBOM interfaces with the standard library Pkg to fill in the SBOM data fields. Information filled out today includes:
- A complete package dependency list including
    - versions in use
    - where the package can be downloaded from
    - SPDX verification code
    - determines the declared license and scans all source files for additional licenses present
- A complete artifact list
    - artifact version resolved to the target platform
        - target platform may be changed by an advanced user
    - where the artifact can be downloaded from
    - download checksum
    - determines the declared license and scans all source files for additional licenses present

Future versions may be able to fill in additional fields including copyright text.

PkgToSoftwareBOM defaults to using the General registry but can use other registries and even mutiple registries as the source(s) of package information.

## What is an SBOM?

An SBOM is a formal, machine-readable inventory of software components and dependencies, information about those components, and their hierarchical relationships. These inventories should be comprehensive – or should explicitly state where they could not be. SBOMs may include open source or proprietary software and can be widely available or access-restricted.

For a further information about SBOMs, their importance and how they can be used please see the Software Bill of Materials website maintained by the [National Telecommuications and Information Administration](https://ntia.gov/page/software-bill-materials)

## Why do you care about SBOMs?

SBOMs are an important component of developing software security practices. US Presidential Executive Order [EO 14028](https://www.whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/) established SBOMs as one method by which the federal government will establish the provenence of software in use. Commercial organizations are also using SBOMs for the same reason.

## What does an SBOM look like?
The file `PkgToSoftwareBOM.spdx.json` at the root of this package is a Developer SBOM of this package.

See examples of User Environment SBOMs in the folder `examples`

## Installation

Type `] add PkgToSoftwareBOM` and then hit ⏎ Return at the REPL. You should see
```julia
pkg> add PkgToSoftwareBOM
```


## How to I use PkgToSoftwareBOM.jl ?

To use this package, just type

```julia
using PkgToSoftwareBOM
```

PkgToSofwareBOM automatically exports the package [SPDX](https://github.com/SamuraiAku/SPDX.jl) which defines the SBOM datatypes and functions for reading and writing. Please see the `SPDX` documentation for full documentation.

There are two use cases envisioned:

- Users: Create an SBOM of your current environment. Submit this file to your organization
- Developers: Create an SBOM to be included with your package source code. This becomes your official declaration of what your package dependencies, copyright, license, and download location.

### !!! Important note about stability and license scanning !!!
PkgToSoftwareBOM uses [LicenseCheck.jl](https://github.com/ericphanson/LicenseCheck.jl) to scan package and artifact directories for license file information. LicenseCheck has been known to occasionally crash when run on Apple Silicon, see [Issue #11](https://github.com/ericphanson/LicenseCheck.jl/issues/11).  I have observed it happening every time when run within VSCode with the julia-vscode extension. There are some early indications this issue may be resolved in Julia 1.11 when it is released, but it is not certain yet.

If you wish to disable license scanning for stability reasons, use the keyword licenseScan when creating a spdxCreationData object (see examples below)

```julia
spdxCreationData(licenseScan= false)
```

### User Environment SBOM

To create an SBOM of your entire environment type:

`sbom= generateSPDX()`

If you wish to not include PkgToSoftwareBOM and SPDX (or some other package) in your SBOM:

```julia
sbom= generateSPDX(spdxCreationData(rootpackages= filter(p-> !(p.first in ["PkgToSoftwareBOM", "SPDX"]), Pkg.project().dependencies)));
```

To write the SBOM to file:
```julia
writespdx(sbom, "myEnvironmentSBOM.spdx.json")
```



### Developer SBOM

A developer SBOM will contain information that PkgToSoftwareBOM cannot determine on its own, such as the package's license and the developer's name. To add this information to the SBOM requires calling generateSPDX() with non-default parameters.

The first thing a developer must determine is the name of their SBOM file. The reason is that PkgToSoftwareBOM computes a checksum of your source code and saves it in the SBOM file. Since the SBOM is included in the package's source tree PkgToSoftwareBOM must know what the file's name is so that it (and others who wish to re-compute the checksum themselves) can skip the file during the calculation. A suggested format for the SBOM filename is `MyPackageName.spdx.json`

By default, PkgToSoftwareBOM will exclude the `.git` folder in your package development directory from the checksum calcuclation. PkgToSoftwareBOM does not process the directions of `.gitignore' files nor does it ignore untracked files. It is recommended that you make sure to commit all your code and restore the repo to a pristine state before running PkgToSoftwareBOM
```
% git clean -fdx
% git status
Your branch is up to date with 'origin/master'.

nothing to commit, working tree clean
```

Now we need to make sure that Pkg is aware that you have bumped the package version. Pkg does not detect the change to version in Project.toml automatically.  While you are developing you generally don't care about this, but it is necessary to get the correct version information into the SBOM

```julia
pkg> update myPackage
    Updating registry at `~/.julia/registries/General.toml`
    Updating `~/JuliaWork/myDevArea/Project.toml`
  [6254a0f9] ~ myPackage v0.1.0 `~/.julia/dev/myPackage` ⇒ v0.1.1 `~/.julia/dev/myPackage`
    Updating `~/JuliaWork/myDevArea/Manifest.toml`
  [6254a0f9] ~ myPackage v0.1.0 `~/.julia/dev/myPackage` ⇒ v0.1.1 `~/.julia/dev/myPackage`
```

Once you have the filename chosen and your repository cleaned up, activate an environment that includes your under development package
```julia
julia> cd("path/to/dev_area")
(@v1.8) pkg> activate .
```

To create your SBOM, start by creating an `spdxPackageInstructions` object which contains SBOM data specific to the package

```julia
# Indicate who you wish to credit as the Originator of the package. For Julia developers, this is generally
# whoever controls the repository the released code is downloaded from. The originator may be a person or an organization
myName= SpdxCreatorV2("Person", "John Doe", "email@loopback.com")  # email may be an empty string if desired
myOrg= SpdxCreatorV2("Organization", "Open-Source Org", "email2@loopback.com")

# For the complete list of available license codes for an SBOM, see the official SPDX License List
#       https://spdx.org/licenses/
# Common Licenses are "MIT", "BSD-3-Clause", "GPL-2.0-or-later"
myLicense= SpdxLicenseExpressionV2("MIT")


myPackage_instr= spdxPackageInstructions(
       spdxfile_toexclude= ["MyPackageName.spdx.json"],
       originator= myName,  # Could be myOrg if appropriate
       declaredLicense= myLicense,
       copyright= "Copyright (c) 2022 John Doe <email@loopback.com> and contributors",
       name= "MyPackageName")
```



The next step is to create an `spdxCreationData` object which contains data for the top-level SBOM structure
```julia
using UUIDs
using Pkg
# Indicate who you wish to credit as creator of this SBOM, whether it is a single person
# or an organization or both. You may credit multiple people and organizations as necessary.
# Including emails in the creator declaration is optional
# Since PkgToSoftwareBOM is filling in most of the document, you can credit the tool as one of the creators as well
myName= SpdxCreatorV2("Person", "John Doe", "email@loopback.com")  # email may be an empty string if desired
myOrg= SpdxCreatorV2("Organization", "Open-Source Org", "email2@loopback.com")
myTool= SpdxCreatorV2("Tool", "PkgToSoftwareBOM.jl", "")

devRoot= filter(p-> p.first == "MyPackageName", Pkg.project().dependencies) # A developer SBOM has a single package at its root

# SPDX namespace provides a unique URI identifier for the SBOM. Best practice, which PkgToSoftwareBOM supports, is to
# provide a URL to this SBOM in the package repository or to a project homepage.
# PkgToSoftwareBOM will append a unique UUID so that the namespace is truly unique.
myNamespace= "https://github.com/myUserName/myPackage.jl/myPackage.spdx.json"

active_pkgs= Pkg.project().dependencies;
SPDX_docCreation= spdxCreationData(
       Name= "MyPackageName.jl Developer SBOM",
       Creators= [myName, myOrg, myTool],
       CreatorComment= "Optional field for general comments about the creation of the SPDX document",
       DocumentComment= "Optional field for to provide comments to the consumers of the SPDX document",
       NamespaceURL= myNamespace,
       rootpackages= devRoot,
       packageInstructions= Dict{UUID, spdxPackageInstructions}(active_pkgs[myPackage_instr.name] => myPackage_instr)  # Your package instructions created above go here
       );

```

Now you can create the SBOM and write it to your development directory.

```julia
sbom= generateSPDX(SPDX_docCreation)
writespdx(sbom, "path/to/package/source/MyPackageName.spdx.json")
```

One case that PkgToSoftwareBOM does not support properly today is when a previous version of the developer's package does not exist in the registry. In that case, the SBOM will list the path to the local copy of the package code, instead of the URL of the repository. This may be fixed in a later version.

## How does PkgToSoftwareBOM support mulitple registries?

The majority of users and developers only ever use the General registry and that is what PkgToSoftwareBOM defaults to to find package information.

If you would like to use a different registry or search multiple registries, you just call `generateSPDX` with two arguments.

For example to create a User Environment SBOM using the General registry and another registry called "PrivateRegistry", type:
```julia
sbom= generateSPDX(spdxCreationData(), ["PrivateRegistry", "General"]);
```

The second argument is a list of all the registries you would like to use. If you have a package that exists in both registries (for example, you've cloned the respository to your local network and you want to list that as the download location), PkgToSoftwareBOM will use the information from the first registry in the list that has valid information and ignore all subsequent registries

## How does PkgToSoftwareBOM determine what the license of the package or artifact is?
PkgToSoftwareBOM scans the entire julia package or artifact for license information.  If the scanning locates a file containing a recognized software license, the license is recorded in the `LicenseInfoFromFiles` property of the SBOM package description but does not record which file(s) the license was found in. The license scan follows these rules (LicenseCheck.jl, version 0.2.2)
- All plaintext files less than 450 KB are scanned

During that search PkgToSoftwareBOM looks for an overall package license in the following locations:
- For Julia packages, in the package root directory
- For artifacts, in the root directory and in the directory `share/licenses`

If files with a valid license are found in the expected location, PkgToSoftwareBOM declares the file where the license takes up the greatest percentage of the total file to be the package license, as you would expect a package license to contain only the license text and nothing else.

## How does PkgToSoftwareBOM target hardware platforms other than the one it is running on?

Advanced users may wish to create an SBOM in which the artifacts are targeted to a different platform than the one that PkgToSoftwareBOM is running on.  For example, create an SBOM for an x86 linux installation from an M1 Macbook.

To do this, the user must first create a platform object describing the target platform.  For example, to create a platform object for the hardware you are currently running on:
```julia
using Base.BinaryPlatforms
myplatform= HostPlatform()
```

Creating a platform object for other hardware is left as an exercise for the advanced user.

To pass the platform object to PkgToSoftwareBOM, use the keyword `TargetPlatform` when creating an `spdxCreationData` object

```julia
SPDX_docCreation= spdxCreationData(TargetPlatform= myplatform)
```