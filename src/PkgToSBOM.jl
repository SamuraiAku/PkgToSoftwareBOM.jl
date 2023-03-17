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
    packageTreeHash::String
    
    # It would be nice to add these fields, but first have to figure out how to resolve version ranges
    #packageCompatibility::Dict{String, Any}
    #PackageDependencies::Dict{String, Any}
end

Base.@kwdef struct sbomData
    packages::Dict{UUID, Pkg.API.PackageInfo}
    registrydata::Dict{UUID, Union{Nothing, Missing, PackageRegistryInfo}}
    packagesinsbom::Set{UUID}= Set{UUID}()
end


Base.@kwdef struct spdxCreationData
    Name::String= "Julia Environment"
    NamespaceURL::Union{AbstractString, Nothing}= nothing
    Creators::Vector{<:AbstractString}= String[]
    CreatorComment::Union{AbstractString, Missing}= missing
    DocumentComment::Union{AbstractString, Missing}= missing
end

include("Registry.jl")
include("sbomBuild.jl")

function isstdlib(name::AbstractString)
    ver= Base.VERSION
    verdir= "v"*string(ver.major)*"."*string(ver.minor)
    stdlist= readdir(joinpath(Sys.BINDIR, "../share/julia/stdlib", verdir))

    return name in stdlist
end

end
