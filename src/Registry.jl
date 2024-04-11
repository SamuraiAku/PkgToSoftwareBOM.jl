# SPDX-License-Identifier: MIT

###############################
# Think of a name that would be good fit for the Pkg API
function registry_packagequery(packages::Dict{UUID, Pkg.API.PackageInfo}, registries::Vector{<:AbstractString})
    if length(registries) == 1
        return _registry_packagequery(packages, registries[1])
    end

    registry_pkg= Dict{UUID, Union{Nothing, Missing, PackageRegistryInfo}}()
    querylist= packages
    for reg in registries
        reglist= _registry_packagequery(querylist, reg)
        registry_pkg= merge(registry_pkg, reglist)
        emptykeys= keys(filter(p-> isnothing(p.second) || ismissing(p.second), registry_pkg))
        querylist= Dict{UUID, Pkg.API.PackageInfo}(k => packages[k] for k in emptykeys)
    end
    return registry_pkg
end

###############################
function _registry_packagequery(packages::Dict{UUID, Pkg.API.PackageInfo}, registry::AbstractString)
    #Get the requested registry
    active_regs= reachable_registries()
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

###############################
function populate_registryinfo(uuid::UUID, package::Pkg.API.PackageInfo, registry::RegistryInstance)
    package.is_tracking_repo && return nothing
    is_stdlib(uuid) && return nothing

    if package.is_tracking_registry || package.is_tracking_path
        # Look up the package in the registry by UUID
        haskey(registry.pkgs, uuid) || return missing
        registryPkg= registry.pkgs[uuid]
    
        # Check package and the registry are using the same name
        (package.name == registryPkg.name) || error("Conflicting package names found: $(string(uuid))=> $(package.name)(environment) vs. $(registryPkg.name)(registry)")
    else
        println("Malformed PackageInfo:  $(string(uuid)) => $(package.name)")  # TODO: Work on this
        return nothing
    end
    
    registryPkgData= registry_info(registryPkg)

    # TODO: Resolve the correct Compat and Deps for this version

    # If actively tracking the registry, verify that the version exists in this registry
    package.is_tracking_registry && !haskey(registryPkgData.version_info, package.version) && return missing

    packageSubdir= isnothing(registryPkgData.subdir) ? "" : registryPkgData.subdir

    # Verify the tree hash in the registry matches the hash in the package
    tree_hash= haskey(registryPkgData.version_info, package.version) ? treehash(registryPkgData, package.version) : nothing
    package.is_tracking_registry && string(tree_hash) !== package.tree_hash && error("Tree hash of $(package.name) v$(string(package.version)) does not match registry:  $(string(package.tree_hash)) (Package) vs. $(treehash(registryPkgData, package.version)) (Registry)")

    pkgRegInfo= PackageRegistryInfo(;
        registryName= registry.name,
        registryURL= registry.repo,
        registryPath= registry.path,
        registryDescription= registry.description,
        packageUUID= uuid,
        packageName= registryPkg.name,
        packageVersion= package.version,
        packageURL= registryPkgData.repo,
        packageSubdir= packageSubdir,
        packageTreeHash= string(tree_hash)
    )
    
    return pkgRegInfo
end