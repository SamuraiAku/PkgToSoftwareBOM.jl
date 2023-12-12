# SPDX-License-Identifier: MIT

module PkgToSoftwareBOM

using Pkg
using UUIDs
using TOML
using Reexport
@reexport using SPDX
using RegistryInstances

export spdxCreationData, spdxPackageInstructions

Base.@kwdef struct PackageRegistryInfo
    registryName::String
    registryURL::String
    registryPath::String
    registryDescription::String
    packageUUID::UUID
    packageName::String
    packageVersion::VersionNumber
    packageURL::String
    packageSubdir::String
    packageTreeHash::Union{String, Nothing}
    
    # It would be nice to add these fields, but first have to figure out how to resolve version ranges
    #packageCompatibility::Dict{String, Any}
    #PackageDependencies::Dict{String, Any}
end

Base.@kwdef struct spdxPackageInstructions
    name::AbstractString
    spdxfile_toexclude::Union{Missing, Vector{String}}= missing
    excluded_files::Vector{String}= String[]
    excluded_dirs::Vector{String}= String[".git"]
    excluded_patterns::Vector{Regex}= Regex[]
    originator::SpdxCreatorV2= SpdxCreatorV2("NOASSERTION") 
    declaredLicense= SpdxLicenseExpressionV2("NOASSERTION")
    copyright::String= "NOASSERTION"
end

Base.@kwdef struct spdxPackageData
    packages::Dict{UUID, Pkg.API.PackageInfo}
    registrydata::Dict{UUID, Union{Nothing, Missing, PackageRegistryInfo}}
    packagesinsbom::Set{UUID}= Set{UUID}()
    packageInstructions::Dict{UUID, spdxPackageInstructions}
end

Base.@kwdef struct spdxCreationData
    Name::String= "Julia Environment"
    NamespaceURL::Union{AbstractString, Nothing}= nothing
    Creators::Vector{SpdxCreatorV2}= SpdxCreatorV2[SpdxCreatorV2("Tool", "PkgToSoftwareBOM.jl", "")]
    CreatorComment::Union{AbstractString, Missing}= missing
    DocumentComment::Union{AbstractString, Missing}= missing
    rootpackages::Dict{String, Base.UUID}= Pkg.project().dependencies
    packageInstructions::Dict{UUID, spdxPackageInstructions}= Dict{UUID, spdxPackageInstructions}()
end

include("Registry.jl")
include("spdxBuild.jl")
include("packageInfo.jl")

function is_stdlib(uuid::UUID)
    return Pkg.Types.is_stdlib(uuid)
end

end
