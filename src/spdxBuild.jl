# SPDX-License-Identifier: MIT

export generateSPDX

function generateSPDX(docData::spdxCreationData= spdxCreationData(), sbomRegistries::Vector{<:AbstractString}= ["General"], envpkgs::Dict{Base.UUID, Pkg.API.PackageInfo}= Pkg.dependencies())
    # Query the registries for package information
    registry_packages= registry_packagequery(envpkgs, sbomRegistries)

    packagebuilddata= spdxPackageData(packages= envpkgs, registrydata= registry_packages, packageInstructions= docData.packageInstructions)

   # Create the SPDX Document
    spdxDoc= SpdxDocumentV2()

    spdxDoc.Name= docData.Name
    createnamespace!(spdxDoc, isnothing(docData.NamespaceURL) ? "https://spdx.org/spdxdocs/" * replace(docData.Name, " "=>"_") : docData.NamespaceURL)
    for c in docData.Creators
        push!(spdxDoc.CreationInfo.Creator, c)
    end
    setcreationtime!(spdxDoc)
    ismissing(docData.CreatorComment) || (spdxDoc.CreationInfo.CreatorComment= docData.CreatorComment)
    ismissing(docData.DocumentComment) || (spdxDoc.DocumentComment= docData.DocumentComment)

    # Add description of the registries in use
    spdxDoc.DocumentComment= (ismissing(spdxDoc.DocumentComment) ? "" : "$(spdxDoc.DocumentComment)\n\n") * "Registries used for populating Package data:\n"
    active_registries= reachable_registries()
    for reg in active_registries
        if reg.name in sbomRegistries
            spdxDoc.DocumentComment= spdxDoc.DocumentComment * 
                "$(reg.name) registry: $(reg.repo)\n$(reg.description)\n\n"
        end
    end

    # Add packages and their relationships to the document
    for (pkg_name, pkg_uuid) in docData.rootpackages
        pkgid= buildSPDXpackage!(spdxDoc, pkg_uuid, packagebuilddata)
        if pkgid isa String
            push!(spdxDoc.Relationships, SpdxRelationshipV2("SPDXRef-DOCUMENT DESCRIBES $(pkgid)"))
        elseif ismissing(pkgid)
            error("generateSPDX():  buildSPDXpackage!() returned an error")
        end
    end
    return spdxDoc
end

function buildSPDXpackage!(spdxDoc::SpdxDocumentV2, uuid::UUID, builddata::spdxPackageData)
    packagedata= builddata.packages[uuid]
    registrydata= builddata.registrydata[uuid]
    packageInstructions= get(builddata.packageInstructions, uuid, missing)
    package= SpdxPackageV2("SPDXRef-$(packagedata.name)-$(uuid)")

    # Check if this package already exists in the SBOM
    (uuid in builddata.packagesinsbom) && (return package.SPDXID)

    # Check if it's a standard library
    is_stdlib(uuid) && return nothing
    
    package.Name= packagedata.name
    package.Version= string(packagedata.version)
    package.Supplier= SpdxCreatorV2("NOASSERTION") # TODO: That would be the person/org who hosts package server?. Julialang would be the supplier for General registry but how would that be determined in generic case
    package.Originator= ismissing(packageInstructions) ?  SpdxCreatorV2("NOASSERTION") : packageInstructions.originator  # TODO: Use the person or group that hosts the repo on Github. Is there an API to query?    
    resolve_pkgsource!(package, packagedata, registrydata)
    package.VerificationCode= spdxpkgverifcode(packagedata.source, packageInstructions)
    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")
    push!(package.LicenseInfoFromFiles, SpdxLicenseExpressionV2("NOASSERTION"))
    package.LicenseDeclared= ismissing(packageInstructions) ? SpdxLicenseExpressionV2("NOASSERTION") : packageInstructions.declaredLicense # TODO: Scan source for licenses and/or query Github API
    package.Copyright= ismissing(packageInstructions) ? "NOASSERTION" : packageInstructions.copyright # TODO:  Scan license files for the first line that says "Copyright"?  That would about work.

    # TODO: Populate Summary with something via a Github API query
    # TODO: Should DetailedDescription be populated with the README?  Or the first 10k characters? Or just a link or path to the README?

    package.Comment= "The SPDX ID field is derived from the UUID that all Julia packages are assigned by their developer to uniquely identify it."

    # Check for dependencies and recursively call this function for any that exist
    for (depname, dep_uuid) in packagedata.dependencies
        depid= buildSPDXpackage!(spdxDoc, dep_uuid, builddata)
        if depid isa String
            push!(spdxDoc.Relationships, SpdxRelationshipV2("$(depid) DEPENDENCY_OF $(package.SPDXID)"))
        elseif ismissing(depid)
            error("buildSPDXpackage!():  recursive call of buildSPDXpackage!() returned an error")
        end
    end

    # Check for artifacts and add them
        # buildSPDXartifactpackage!
        # builddata should include the host platform so that user can override for another if needed
        #   Should there be an option for computing all the possible architecture/os downloads and adding them?
        #       That different from generating a BOM for the current user environment which is what we advertise doing now.
        #       That requires downloading all possible artifacts and then deleting ones that don't belong and that weren't already present.
        #       This feels like a future feature. Focus on just the host platform to start.
        # Always include lazy artifacts, should they be optional dependencies?
        #   That would require downloading lazy artifacts if they are not already downloaded. Not too big a deal.
        # Should artifacts be runtime dependencies or just dependencies?
        # If downloads are required that we should test or otherwise allow for cases where the download will fail because there is no netowrk connection
        # And fill in the package fields appropriately
        # SourceInfo could include the platofrm info
        # The git-tree-sha1 hash identifies the artifact in Julia, so that should be part of the SPDX-Ref + it's name
    buildSPDXartifactpackage!(spdxDoc, packagedata)

    push!(spdxDoc.Packages, package)
    push!(builddata.packagesinsbom, uuid)
    return package.SPDXID
end

function buildSPDXartifactpackage!(spdxDoc::SpdxDocumentV2, packagedata::Pkg.API.PackageInfo, platform::AbstractPlatform= HostPlatform())
    filenames= ["Artifacts.toml", "JuliaArtifacts.toml"]
    filecheck= isfile.(joinpath.(packagedata.source, filenames))
    any(filecheck) || return nothing

    artifact_toml= joinpath(packagedata.source, filenames[findfirst(filecheck)])
    artifact_data= select_downloadable_artifacts(artifact_toml; platform= platform, include_lazy= true) # Reads (Julia)Artifacts.toml and 
                                                                                                        # selects the set of artifacts appropriate to the target platform
    for (artifact_name, artifact) in artifact_data

    end

end

function spdxpkgverifcode(source::AbstractString, packageInstructions::Union{Missing, spdxPackageInstructions})
    if ismissing(packageInstructions)
        packageInstructions= spdxPackageInstructions(name= "") # go with the defaults
    end

    excluded_files= copy(packageInstructions.excluded_files)
    ismissing(packageInstructions.spdxfile_toexclude) || append!(excluded_files, packageInstructions.spdxfile_toexclude)
    verifcode= spdxchecksum("SHA1", source, excluded_files, packageInstructions.excluded_dirs, packageInstructions.excluded_patterns)
    return SpdxPkgVerificationCodeV2(bytes2hex(verifcode), packageInstructions.spdxfile_toexclude)
end