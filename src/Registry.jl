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

# Think of a name that would be good fit for the Pkg API
function registry_packagequery(packages::Dict{Base.UUID, Pkg.API.PackageInfo}; registry::AbstractString= "General")
    #Get the requested registry
    active_regs= Pkg.Registry.reachable_registries()
    selected_registry= nothing
    for reg in active_regs
        if reg.name == registry
            selected_registry= reg
            break
        end
    end

    if isnothing(selected_registry)
        error("""Registry \"$(registry)\" cannot be found""")
    end
    println("""Using registry "$(selected_registry.name)" @ $(selected_registry.path)""")

    registry_pkg= Dict{Base.UUID, Union{Nothing, Missing, PackageRegistryInfo}}(k => populate_registryinfo(k, packages[k], selected_registry) for k in keys(packages))
    
    return registry_pkg
end

function populate_registryinfo(uuid::UUID, package::Pkg.API.PackageInfo, registry::Pkg.Registry.RegistryInstance; override::Bool= true)
    (package.is_tracking_path || package.is_tracking_repo) && return nothing

    if package.is_tracking_registry
        isnothing(package.version) && return nothing  # Typically this means the package is an stdlib

        # Look up the package in the registry by UUID
        haskey(registry.pkgs, uuid) || return missing
        registryPkg= registry.pkgs[uuid]
    
        # Validation checks
        (package.name == registryPkg.name) || error("Conflicting package names found: $(string(uuid))=> $(package.name)(environment) vs. $(registryPkg.name)(registry)")
    else
        prinln("Error in packageInfo")  #TODO Work on this
        return nothing
    end
    
    registryPath= registryPkg.path
    #Compat= TOML.parse(registry.in_memory_registry[registryPath*"/Compat.toml"])
    #Deps= TOML.parse(registry.in_memory_registry[registryPath*"/Deps.toml"])
    Package= TOML.parse(registry.in_memory_registry[registryPath*"/Package.toml"])
    Versions= TOML.parse(registry.in_memory_registry[registryPath*"/Versions.toml"])

    # TODO: Resolve the correct Compat and Deps for this version

    # Verify that the version exists in this registry
    haskey(Versions, string(package.version)) || return missing

    # Verify the tree hash in the registry matches the hash in the package
    isnothing(package.tree_hash) && return nothing  # This is probably an stdlib which is also in the registry for some reason
    Versions[string(package.version)]["git-tree-sha1"] == package.tree_hash || error("Tree hash of $(package.name) v$(string(package.version)) does not match registry:  $(string(package.tree_hash)) (Package) vs. $(Versions[string(package.version)]["git-tree-sha1"])")

    pkgRegInfo= PackageRegistryInfo(;
        registryName= registry.name,
        registryURL= registry.repo,
        registryPath= registry.path,
        registryDescription= registry.description,
        packageUUID= uuid,
        packageName= registryPkg.name,
        packageVersion= package.version,
        packageURL= Package["repo"],
        packageTreeHash= Versions[string(package.version)]["git-tree-sha1"]
    )
    
    return pkgRegInfo
end