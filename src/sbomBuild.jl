export generateSPDX

function generateSPDX(docData::spdxCreationData, sbomRegistries::Vector{<:AbstractString}= ["General"], envpkgs::Dict{Base.UUID, Pkg.API.PackageInfo}= Pkg.dependencies())
    # Query the registries for package information
    registry_packages= registry_packagequery(envpkgs, sbomRegistries)

    packagebuilddata= spdxPackageData(packages= envpkgs, registrydata= registry_packages, packagebuildinstructions= docData.packagebuildinstructions)

   # Create the SPDX Document
    spdxDoc= SpdxDocumentV2()

    spdxDoc.Name= docData.Name
    createnamespace!(spdxDoc, isnothing(docData.NamespaceURL) ? "https://spdx.org/spdxdocs/" * replace(docData.Name, " "=>"_") : docData.NamespaceURL)
    push!(spdxDoc.CreationInfo.Creator, SpdxCreatorV2("Tool", "PkgToSBOM.jl", ""))
    for c in docData.Creators
        push!(spdxDoc.CreationInfo.Creator(SpdxCreatorV2(c)))
    end
    setcreationtime!(spdxDoc)
    ismissing(docData.CreatorComment) || (spdxDoc.CreationInfo.CreatorComment= docData.CreatorComment)
    ismissing(docData.DocumentComment) || (spdxDoc.DocumentComment= docData.DocumentComment)

    # Add description of the registries in use
    spdxDoc.DocumentComment= (ismissing(spdxDoc.DocumentComment) ? "" : "$(spdxDoc.DocumentComment)\n\n") * "Registries used for populating Package data:\n"
    active_registries= Pkg.Registry.reachable_registries()
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
    package= SpdxPackageV2("SPDXRef-$(packagedata.name)-$(uuid)")

    # Check if this package already exists in the SBOM
    (uuid in builddata.packagesinsbom) && (return package.SPDXID)

    # Check if it's a standard library
    is_stdlib(uuid) && return nothing

    # Build the SPDX package
    # The contents of the SPDX package depend on whether Pkg is tracking the package via:
    #   1) A package registry
    #   2) Connecting directly with a git repository
    #   3) Source code on a locally accessible storage device (i.e. no source control)
    #   4) Is the package a package under development that will eventually be added to a registry
    #       a) If marked as such, there should be a note saying so in the package
    
    package.Name= packagedata.name
    package.Version= string(packagedata.version)
    package.Supplier= SpdxCreatorV2("NOASSERTION") # TODO: That would be the person/org who hosts package server?. Julialang would be the supplier for General registry but how would that be determined in generic case
    package.Originator= SpdxCreatorV2("NOASSERTION")   # TODO: Use the person or group that hosts the repo on Github. Is there an API to query?
    
    resolve_pkgsource!(package, packagedata, registrydata)

    # TODO: Get the verification code/checksum correctly computed
    #verifcode= spdxchecksum("SHA1", packagedata.source, 
    #                        isnothing(dev_package_data)    ? builddata.excluded_files : append!(String[], builddata.excluded_files, [builddata.dev_package_data.spdxfile]),
    #                        (packagedata.is_tracking_repo) ? append!(String[], builddata.excluded_dirs, [".git"]) : builddata.excluded_dirs, 
    #                        builddata.excluded_patterns)
    #package.VerificationCode= SpdxPkgVerificationCodeV2(bytes2hex(verifcode), String[developerSPDXfile])
    
    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")
    push!(package.LicenseInfoFromFiles, SpdxLicenseExpressionV2("NOASSERTION"))
    package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION") # TODO: Scan source for licenses and/or query Github API
    package.Copyright= "NOASSERTION" # TODO:  Look for a copyright file and include the first 10k characters?  Would want a modificstion to SPDX so that's not all printed out.

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

    push!(spdxDoc.Packages, package)
    push!(builddata.packagesinsbom, uuid)
    return package.SPDXID
end


function resolve_pkgsource!(package::SpdxPackageV2, packagedata::Pkg.API.PackageInfo, registrydata::Union{Nothing, Missing, PackageRegistryInfo})
    if packagedata.is_tracking_registry
        # Simplest and most common case is if you are tracking a registered package
        package.DownloadLocation= SpdxDownloadLocationV2("git+$(registrydata.packageURL)@v$(packagedata.version)")
        package.HomePage= registrydata.packageURL
        package.SourceInfo= "Package Information is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)"
        # Don't set FileName in this case.
    elseif packagedata.is_tracking_repo
        # Next simplest case is if you are directly tracking a repository
        package.DownloadLocation= SpdxDownloadLocationV2("git+$(packagedata.git_source)@$(packagedata.git_revision)")
        package.HomePage= packagedata.git_source
        package.SourceInfo= "$(packagedata.name) is directly tracking a git repository."
        # Don't set FileName in this case.
    elseif packagedata.is_tracking_path
        # The hard case is if you are working off a local file path.  Is it really just a path, or are you dev'ing a package?
        # Use the registry data if it exists
        if registrydata isa PackageRegistryInfo
            package.DownloadLocation= SpdxDownloadLocationV2("git+$(registrydata.packageURL)@v$(packagedata.version)")
            package.HomePage= registrydata.packageURL
            package.SourceInfo= "Package Information is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)"
            # TODO: See if this version exists in the registry. If it already does, then that's an error/warning on this dev version
        else
            # TODO: This may be a dev'ed version of a direct track from a repository. Figure out how to determine that
            package.DownloadLocation= SpdxDownloadLocationV2("NOASSERTION")
            package.HomePage= "NOASSERTION"
            package.FileName= packagedata.source
        end
    else
        # This should not happen unless there has been a breaking change in Pkg
        error("PkgToSBOM.resolve_pkgsource!():  Unable to resolve. Maybe the Pkg source has changed in a breaking way?")
    end

    return nothing
end