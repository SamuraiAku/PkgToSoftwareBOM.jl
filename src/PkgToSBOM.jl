module PkgToSBOM

using Pkg
using UUIDs
using TOML

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
    packages::Dict{Base.UUID, Pkg.API.PackageInfo}
    registrypackagedata::Dict{Base.UUID, Union{Nothing, Missing, PackageRegistryInfo}}
    packagesinsbom::Set{UUID}= Set{UUID}()
end

include("Registry.jl")

end
