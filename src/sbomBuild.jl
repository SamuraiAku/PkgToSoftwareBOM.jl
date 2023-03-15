export generateSPDX

function generateSPDX(docData::spdxCreationData= spdxCreationData(), toplevel::Dict{String, Base.UUID}= Pkg.project().dependencies, sbomRegistries::Vector{<:AbstractString}= ["General"], envpkgs::Dict{Base.UUID, Pkg.API.PackageInfo}= Pkg.dependencies())
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
    isnothing(docData.CreatorComment) || (spdxDoc.CreationInfo.CreatorComment= docData.CreatorComment)
    isnothing(docData.DocumentComment) || (spdxDoc.DocumentComment= docData.DocumentComment)

    
    # Recursive calling of the package function
    # Call once here for each top level
    # The document is one of the parameters
    # So is the envpkgs, and the uuid associated with the package we want to describe
    # And the last parameter is maybe a Dict that tracks what packages already exist?
    builddata= sbomData(packages= envpkgs, registrydata= registry_packages)
    for (pkg_name, pkg_uuid) in toplevel
        pkg= buildSPDXpackage!(spdxDoc, pkg_uuid, builddata)
        println(pkg)
        if pkg isa SpdxPackageV2
            println(pkg)
            push!(spdxDoc.Packages, pkg)
            push!(spdxDoc.Relationships, SpdxRelationshipV2("SPDXRef-DOCUMENT DESCRIBES $(pkg.SPDXID)"))
            push!(builddata.packagesinsbom, pkg_uuid)
        elseif ismissing(pkg)
            error("generateSPDX():  buildSPDXpackage!() returned an error")
        end
    end
    return spdxDoc
end

# Need a function to check if a package is part of stdlib. Different list for each version of Julia
# So that I don't add them to the package list

# Need some kind of flag to indicate when the package is being generated for a package under development.

function buildSPDXpackage!(spdxdoc::SpdxDocumentV2, uuid::UUID, builddata::sbomData)
    # Check if this package already exists in the SBOM
    (uuid in builddata.packagesinsbom) && return nothing

    packagedata= builddata.packages[uuid]
    registrydata= builddata.registrydata[uuid]

    # Check if it's a standard library
    isnothing(registrydata) && isstdlib(packagedata.name) && return nothing

    # Oddball checks. Registry is nothing but not a stdlib.
        # Check if it tracks a repo or a path. We can make a package for that.

    # If it is missing just return? Then it's tracking a regsitry but it's not in this list.
    # Create the package but note can find the registry info.
    
    # Build the SPDX package
    # The contents of the SPDX package depend on whether Pkg is tracking the package via:
    #   1) A package registry
    #   2) Connecting directly with a git repository
    #   3) Source code on a locallly accessible storage device (i.e. no source control)
    
    package= SpdxPackageV2("SPDXRef-$(uuid)")
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
    # TODO:  Code for computing checksum if tracking repo.  The git commit hash is not what they want. It's the tree_hash 
    # TODO:  Code for adding a verification code is tracking path or user is a package developer
    (registrydata isa PackageRegistryInfo) && push!(package.Checksums, SpdxChecksumV2("SHA1", packagedata.tree_hash))
    
    package.HomePage= (registrydata isa PackageRegistryInfo) ? registrydata.packageURL :
                              (packagedata.is_tracking_repo) ? packagedata.git_source :
                                                               "NONE"

    package.SourceInfo= (registrydata isa PackageRegistryInfo) ? "Package Information is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)\n$(registrydata.registryDescription)" :
                                (packagedata.is_tracking_repo) ?  missing : 
                                                                 "Package Source is a local file path. No known download location."

    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")
    push!(package.LicenseInfoFromFiles, SpdxLicenseExpressionV2("NOASSERTION"))
    package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION") # TODO: Scan source for licenses and/or query Github API
    package.Copyright= "NOASSERTION" # TODO:  Look for a copyright file and include the first 10k characters?  Would want a modificstion to SPDX so that's not all printed out.

    # TODO: Populate Summary with something via a Github API query
    # TODO: Should DetailedDescription be populated with the README?  Or the first 10k characters?

    package.Comment= "The SPDX ID field is derived from the UUID that all Julia packages are assigned by their developer to uniquely identify it."
    
    # Check for dependencies and recursive call this function for any that exist
    # Then add the relationship between the dependency and this package


    return package
end