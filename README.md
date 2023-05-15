# PkgToSBOM.jl

This package produces a Software Bill of Materials (SBOM) describing your Julia environment. At this time, the SBOM produced is in the ([SPDX](https://github.com/SamuraiAku/SPDX.jl)) format.  Contributions to support other SBOM formats are welcome.

I created PkgToSBOM.jl to help the Julia ecosystem get prepared for the emerging future of software supply chain security. If we want to see Julia adoption to continue to grow, then we need to be able to easily create SBOMs to supply to the organizations using Julia packages.

PkgToSBOM interfaces with the standard library Pkg to fill in the SBOM data fields. Information filled out today includes a complete dependency list, versions in use, where the package can be downloaded from, and a checksum. Future versions may be able to fill in additional fields including copyright text and software license.

PkgToSBOM defaults to using the General registry but can use other registries and even mutiple registries as the source(s) of package information.

## What is an SBOM?

An SBOM is a formal, machine-readable inventory of software components and dependencies, information about those components, and their hierarchical relationships. These inventories should be comprehensive – or should explicitly state where they could not be. SBOMs may include open source or proprietary software and can be widely available or access-restricted.

For a further information about SBOMs, their importance and how they can be used please see the Software Bill of Materials website maintained by the [National Telecommuications and Information Administration](https://ntia.gov/page/software-bill-materials)

## Why do you care about SBOMs?

SBOMs are an important component of developing software security practices. US Presidential Executive Order [EO 14028](https://www.whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/) established SBOMs as one method by which the federal government will establish the provenence of software in use. Commercial organizations are also using SBOMs for the same reason.


## Installation

Type `] add PkgToSBOM` and then hit ⏎ Return at the REPL. You should see `pkg> add PkgToSBOM`.


## How to I use PkgToSBOM.jl ?

There are two use cases envisioned

- Users: Create an SBOM of your current environment. Submit this file to your organization
- Developers: Create an SBOM to be included with your package source code. This becomes your official declaration of what your package dependencies, copyright, license, and download location.

### User Environment SBOM

To create an SBOM of your entire environment type:

`sbom= generateSPDX()`

If you wish to not include PkgToSBOM and SPDX (or some other package) in your SBOM:

`sbom= generateSPDX(spdxCreationData(rootpackages= filter(p-> !(p.first in ["PkgToSBOM", "SPDX"]), Pkg.project().dependencies)));`

To write the SBOM to file:
```julia
using SPDX
writespdx(sbom, "myEnvironmentSBOM.spdx.json")
```



### Developer SBOM

A developer SBOM will contain information that PkgToSBOM cannot determine on its own, such as the package's license and the developer's name. To add this information to the SBOM requires calling generateSPDX() with non-default parameters.

The first thing a developer must determine is the name of their SBOM file. The reason is that PkgToSBOM computes a checksum of your source code and saves it in the SBOM file. Since the SBOM is included in the package's source tree PkgToSBOM must know what the file's name is so that it (and others who wish to re-compute the checksum themselves) can skip the file during the calculation. A suggested format for the SBOM filename is `MyPackageName.spdx.json`

By default, PkgToSBOM will exclude the `.git` folder in your package development directory from the checksum calcuclation. PkgToSBOM does not process the directions of `.gitignore' files nor does it ignore untracked files. It is recommended that you make sure to commit all your code and restore the repo to a pristine state before running PkgToSBOM
```
% git clean -fdx
% git status
Your branch is up to date with 'origin/master'.

nothing to commit, working tree clean
```

Once you have the filename chosen and your repository cleaned up, activate an environment that includes your under development package
```julia
julia> cd("path/to/dev_area")
(@v1.8) pkg> activate .
```

To create your SBOM, start by creating an `spdxPackageInstructions` object which contains SBOM data specific to the package

```julia
using SPDX
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
using SPDX
using UUIDs
using Pkg
# Indicate who you wish to credit as creator of this SBOM, whether it is a single person 
# or an organization or both. You may credit multiple people and organizations as necessary.
# Including emails in the creator declaration is optional
# Since PkgToSBOM is filling in most of the document, you can credit the tool as one of the creators as well 
myName= SpdxCreatorV2("Person", "John Doe", "email@loopback.com")  # email may be an empty string if desired
myOrg= SpdxCreatorV2("Organization", "Open-Source Org", "email2@loopback.com")
myTool= SpdxCreatorV2("Tool", "PkgToSBOM.jl", "")

devRoot= filter(p-> p.first == "MyPackageName", Pkg.project().dependencies) # A developer SBOM has a single package at its root

# SPDX namespace provides a unique URI identifier for the SBOM. Best practice, which PkgToSBOM supports, is to
# provide a URL to this SBOM in the package repository or to a project homepage.  
# PkgToSBOM will append a unique UUID so that the namespace is truly unique.
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
using SPDX
writespdx(sbom, "path/to/package/source/MyPackageName.spdx.json")
```

One case that PkgToSBOM does not support properly today is when a previous version of the developer's package does not exist in the registry. In that case, the SBOM will list the path to the local copy of the package code, instead of the URL of the repository. This may be fixed in a later version.

## How does PkgToSBOM support mulitple registries?

The majority of users and developers only ever use the General registry and that is what PkgToSBOM defaults to to find package information.

If you would like to use a different registry or search multiple registries, you just call `generateSPDX` with two arguments.

For example to create a User Environment SBOM using the General registry and another registry called "PrivateRegistry", type:
```julia
sbom= generateSPDX(spdxCreationData(), ["PrivateRegistry", "General"]);
```

The second argument is a list of all the registries you would like to use. If you have a package that exists in both registries (for example, you've cloned the respository to your local network and you want to list that as the download location), PkgToSBOM will use the information from the first registry in the list that has valid information and ignore all subsequent registires
