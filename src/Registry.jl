# SPDX-License-Identifier: MIT

###############################
# Think of a name that would be good fit for the Pkg API
function registry_packagequery(packages::Dict{UUID, Pkg.API.PackageInfo}, registries::Vector{<:AbstractString}, use_packageserver::Bool)
    if use_packageserver
        server_registry_info= pkg_server_registry_info()
    else
        server_registry_info= nothing
    end
    
    if length(registries) == 1
        return _registry_packagequery(packages, registries[1], server_registry_info)
    end

    registry_pkg= Dict{UUID, Union{Nothing, Missing, PackageRegistryInfo}}()
    querylist= packages
    for reg in registries
        reglist= _registry_packagequery(querylist, reg, server_registry_info)
        registry_pkg= merge(registry_pkg, reglist)
        emptykeys= keys(filter(p-> isnothing(p.second) || ismissing(p.second), registry_pkg))
        querylist= Dict{UUID, Pkg.API.PackageInfo}(k => packages[k] for k in emptykeys)
    end
    return registry_pkg
end

###############################
function _registry_packagequery(packages::Dict{UUID, Pkg.API.PackageInfo}, registry::AbstractString, server_registry_info)
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

    if isnothing(server_registry_info)
        packageserver= nothing
    else
        server, registry_info = server_registry_info
        if selected_registry.uuid in keys(registry_info)
            packageserver= "$server/package"
        else
            packageserver= nothing
        end
    end
    
    registry_pkg= Dict{Base.UUID, Union{Nothing, Missing, PackageRegistryInfo}}(k => populate_registryinfo(k, packages[k], selected_registry, packageserver) for k in keys(packages))
    
    return registry_pkg
end

###############################
function populate_registryinfo(uuid::UUID, package::Pkg.API.PackageInfo, registry::RegistryInstance, packageserver::Union{String, Nothing})
    package.is_tracking_repo && return nothing

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

    # Verify that the version exists in this registry
    haskey(registryPkgData.version_info, package.version) || return missing

    packageSubdir= isnothing(registryPkgData.subdir) ? "" : registryPkgData.subdir

    tree_hash= haskey(registryPkgData.version_info, package.version) ? treehash(registryPkgData, package.version) : nothing

    # Verify the tree hash in the registry matches the hash in the package. This check usually (always?) fails with an stdlib, even if it is tracked in the registry, becuase package.tree_hash is nothing.
    if !is_stdlib(uuid)
        package.is_tracking_registry && string(tree_hash) !== package.tree_hash && error("Tree hash of $(package.name) v$(string(package.version)) does not match registry:  $(string(package.tree_hash)) (Package) vs. $(treehash(registryPkgData, package.version)) (Registry)")
    end

    packageserverURL= isnothing(packageserver) ? nothing : packageserver * "/$(uuid)/$(package.tree_hash)"

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
        packageTreeHash= string(tree_hash),
        packageserverURL= packageserverURL
    )
    
    return pkgRegInfo
end

################################
## The code below has been copied from Julia Package Manager v1.10.4 and modified as needed
##     https://github.com/JuliaLang/Pkg.jl/tree/v1.10.4
#  
#  Copyright (c) 2017-2021: Stefan Karpinski, Kristoffer Carlsson, Fredrik Ekre, David Varela, Ian Butterworth, and contributors: 
#  https://github.com/JuliaLang/Pkg.jl/graphs/contributors
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#  
#  The above copyright notice and this permission notice shall be included in all
#  copies or substantial portions of the Software.
#  
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#  SOFTWARE.

function pkg_server()
    server = get(ENV, "JULIA_PKG_SERVER", "https://pkg.julialang.org")
    isempty(server) && return nothing
    startswith(server, r"\w+://") || (server = "https://$server")
    return rstrip(server, '/')
end

################################
function pkg_server_registry_info()
    registry_info = Dict{UUID, Base.SHA1}()
    server = pkg_server()
    server === nothing && return nothing
    tmp_path = tempname()
    download_ok = false
    try
        f = retry(delays = fill(1.0, 3)) do
            Downloads.download("$server/registries", tmp_path)
        end
        f()
        download_ok = true
    catch err
        @warn "Could not download $server/registries, unable to fill in package server URLs" exception=err
    end
    download_ok || return nothing
    open(tmp_path) do io
        for line in eachline(io)
            if (m = match(r"^/registry/([^/]+)/([^/]+)$", line)) !== nothing
                uuid = UUID(m.captures[1]::SubString{String})
                hash = Base.SHA1(m.captures[2]::SubString{String})
                registry_info[uuid] = hash
            end
        end
    end
    Base.rm(tmp_path, force=true)
    return server, registry_info
end