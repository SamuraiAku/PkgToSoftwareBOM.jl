# SPDX-License-Identifier: MIT

using PkgToSBOM
using SPDX
using Pkg
using UUIDs

spdxFileName= "PkgToSBOM.spdx.json"
myName= SpdxCreatorV2("Person", "Simon Avery", "savery@ieee.org")
myTool= SpdxCreatorV2("Tool", "PkgToSBOM.jl", "")
myLicense= SpdxLicenseExpressionV2("MIT")

myPackage_instr= spdxPackageInstructions(
              spdxfile_toexclude= [spdxFileName],
              originator= myName,
              declaredLicense= myLicense,
              copyright= "Copyright (c) 2023 Simon Avery <savery@ieee.org> and contributors",
              name= "PkgToSBOM")

devRoot= filter(p-> p.first == "PkgToSBOM", Pkg.project().dependencies)
myNamespace= "https://github.com/SamuraiAku/PkgToSBOM.jl/blob/main/PkgToSBOM.spdx.json"

active_pkgs= Pkg.project().dependencies;
SPDX_docCreation= spdxCreationData(
              Name= "PkgToSBOM.jl Developer SBOM",
              Creators= [myName, myTool],
              NamespaceURL= myNamespace,
              rootpackages= devRoot,
              packageInstructions= Dict{UUID, spdxPackageInstructions}(active_pkgs[myPackage_instr.name] => myPackage_instr)
            )

sbom= generateSPDX(SPDX_docCreation)
writespdx(sbom, spdxFileName)