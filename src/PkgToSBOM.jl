module PkgToSBOM

using Pkg
using UUIDs
using TOML
using SPDX

export spdxCreationData

Base.@kwdef struct PackageRegistryInfo
    registryName::String
    registryURL::String
    registryPath::String
    registryDescription::String
    packageUUID::UUID
    packageName::String
    packageVersion::VersionNumber
    packageURL::String
    packageTreeHash::Union{String, Nothing}
    
    # It would be nice to add these fields, but first have to figure out how to resolve version ranges
    #packageCompatibility::Dict{String, Any}
    #PackageDependencies::Dict{String, Any}
end

Base.@kwdef struct spdxPackageChecksumInstructions
    name::AbstractString
    spdxfile_toexclude::Union{Missing, Vector{String}}= missing
    excluded_files::Vector{String}= String[]
    excluded_dirs::Vector{String}= String[".git"]
    excluded_patterns::Vector{Regex}= Regex[]
end

Base.@kwdef struct spdxPackageData
    packages::Dict{UUID, Pkg.API.PackageInfo}
    registrydata::Dict{UUID, Union{Nothing, Missing, PackageRegistryInfo}}
    packagesinsbom::Set{UUID}= Set{UUID}()
    checksuminstructions::Dict{UUID, spdxPackageChecksumInstructions}
end

Base.@kwdef struct spdxCreationData
    Name::String= "Julia Environment"
    NamespaceURL::Union{AbstractString, Nothing}= nothing
    Creators::Vector{<:AbstractString}= String[]
    CreatorComment::Union{AbstractString, Missing}= missing
    DocumentComment::Union{AbstractString, Missing}= missing
    rootpackages::Dict{String, Base.UUID}= Pkg.project().dependencies
    checksuminstructions::Dict{UUID, spdxPackageChecksumInstructions}= Dict{UUID, spdxPackageChecksumInstructions}()
end

include("Registry.jl")
include("sbomBuild.jl")

function is_stdlib(uuid::UUID)
    return Pkg.Types.is_stdlib(uuid)
end

end
