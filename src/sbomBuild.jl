export generateSPDX

# I suppose I should add test only dependencies as well? They're all downloaded. Would have to parse [extras] in Project and test/Project.toml? Or is there a better way?
function generateSPDX(toplevel::Dict{String, Base.UUID}= Pkg.project().dependencies, docData::spdxCreationData= spdxCreationData(), sbomRegistries::Vector{<:AbstractString}= ["General"], envpkgs::Dict{Base.UUID, Pkg.API.PackageInfo}= Pkg.dependencies())
    # Query the registries for package information
    registry_packages= registry_packagequery(envpkgs, sbomRegistries)

    # Create the SPDX Document
    spdxDoc= SpdxDocumentV2()  # Do I pass a structure here? or just add them by hand from the input object. 
                                # Have to do that unless I want to add something to SPDX. Maybe later once I see how this works out.
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

    # Add packages and their relationships
    builddata= sbomData(packages= envpkgs, registrydata= registry_packages)
    for (pkg_name, pkg_uuid) in toplevel
        pkgid= buildSPDXpackage!(spdxDoc, pkg_uuid, builddata)
        if pkgid isa String
            push!(spdxDoc.Relationships, SpdxRelationshipV2("SPDXRef-DOCUMENT DESCRIBES $(pkgid)"))
        elseif ismissing(pkgid)
            error("generateSPDX():  buildSPDXpackage!() returned an error")
        end
    end
    return spdxDoc
end

# Need some kind of flag to indicate when the package is being generated for a package under development.

function buildSPDXpackage!(spdxDoc::SpdxDocumentV2, uuid::UUID, builddata::sbomData)
    packagedata= builddata.packages[uuid]
    registrydata= builddata.registrydata[uuid]
    package= SpdxPackageV2("SPDXRef-$(packagedata.name)-$(uuid)")

    # Check if this package already exists in the SBOM
    (uuid in builddata.packagesinsbom) && (return package.SPDXID)

    # Check if it's a standard library
    isnothing(registrydata) && isstdlib(packagedata.name) && return nothing

    # Build the SPDX package
    # The contents of the SPDX package depend on whether Pkg is tracking the package via:
    #   1) A package registry
    #   2) Connecting directly with a git repository
    #   3) Source code on a locallly accessible storage device (i.e. no source control)
    
    package.Name= packagedata.name
    package.Version= string(packagedata.version)
    packagedata.is_tracking_path && (package.FileName= packagedata.source)
    package.Supplier= SpdxCreatorV2("NOASSERTION") # TODO: That would be the person/org who hosts package server?. Julialang would be the supplier for General registry but how would that be determined in generic case
    package.Originator= SpdxCreatorV2("NOASSERTION")   # TODO: Use the person or group that hosts the repo on Github. Is there an API to query?
    
    package.DownloadLocation= SpdxDownloadLocationV2(
        (registrydata isa PackageRegistryInfo) ? "git+$(registrydata.packageURL)@v$(packagedata.version)" :
                (packagedata.is_tracking_repo) ? "git+$(packagedata.git_source)@$(packagedata.git_revision)" :
                                                 "NONE"
    )
    # TODO:  Code for computing or retrieving checksum if tracking repo.  The git commit hash is not what they want. It's the tree_hash 
    # TODO:  Code for adding a verification code is tracking path or user is a package developer
    (registrydata isa PackageRegistryInfo) && (package.VerificationCode= SpdxPkgVerificationCodeV2(packagedata.tree_hash))
 
    package.HomePage= (registrydata isa PackageRegistryInfo) ? registrydata.packageURL :
                              (packagedata.is_tracking_repo) ? packagedata.git_source :
                                                               "NONE"

    package.SourceInfo= (registrydata isa PackageRegistryInfo) ? "Package Information is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)" :
                                (packagedata.is_tracking_repo) ?  missing : 
                                                                 "Package Source is a local file path. No known download location."

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