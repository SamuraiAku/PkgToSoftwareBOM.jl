# SPDX-License-Identifier: MIT

export generateSPDX

function generateSPDX(docData::spdxCreationData= spdxCreationData(), sbomRegistries::Vector{<:AbstractString}= ["General"], envpkgs::Dict{Base.UUID, Pkg.API.PackageInfo}= Pkg.dependencies())
    # Query the registries for package information
    registry_packages= registry_packagequery(envpkgs, sbomRegistries)

    packagebuilddata= spdxPackageData(targetplatform= docData.TargetPlatform, packages= envpkgs, registrydata= registry_packages, packageInstructions= docData.packageInstructions)

   # Create the SPDX Document
    spdxDoc= SpdxDocumentV2()

    spdxDoc.Name= docData.Name
    createnamespace!(spdxDoc, isnothing(docData.NamespaceURL) ? "https://spdx.org/spdxdocs/" * replace(docData.Name, " "=>"_") : docData.NamespaceURL)
    for c in docData.Creators
        push!(spdxDoc.CreationInfo.Creator, c)
    end
    setcreationtime!(spdxDoc)

    # Add any creator comments from docData and then append the Target Platform information
    ismissing(docData.CreatorComment) || (spdxDoc.CreationInfo.CreatorComment= docData.CreatorComment)

    if (ismissing(spdxDoc.CreationInfo.CreatorComment))  spdxDoc.CreationInfo.CreatorComment= ""
                                                   else  spdxDoc.CreationInfo.CreatorComment*= "\n" end

    spdxDoc.CreationInfo.CreatorComment*= string("Target Platform: ", string(docData.TargetPlatform))

    ismissing(docData.DocumentComment) || (spdxDoc.DocumentComment= docData.DocumentComment)

    # Add description of the registries in use
    spdxDoc.DocumentComment= (ismissing(spdxDoc.DocumentComment) ? "" : "$(spdxDoc.DocumentComment)\n\n") * "Registries used for populating Package data:"
    active_registries= reachable_registries()
    for reg in active_registries
        if reg.name in sbomRegistries
            spdxDoc.DocumentComment= spdxDoc.DocumentComment * 
                "\n$(reg.name) registry: $(reg.repo)\n$(reg.description)"
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

## Building an SPDX Package for a Julia package
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
    package.Summary= "This is a Julia package, written in the Julia language."

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
    artifact_toml= find_artifacts_toml(packagedata.source)
    if artifact_toml isa String
        resolved_artifact_data= select_downloadable_artifacts(artifact_toml; platform= builddata.targetplatform, include_lazy= true)
        for (artifact_name, artifact) in resolved_artifact_data
            depid= buildSPDXpackage!(spdxDoc, artifact_name, artifact, builddata)
            if depid isa String
                push!(spdxDoc.Relationships, SpdxRelationshipV2("$(depid) RUNTIME_DEPENDENCY_OF $(package.SPDXID)"))
            elseif ismissing(depid)
                error("buildSPDXpackage!():  call of buildSPDXpackage!() for an artifact package returned an error")
            end
        end
    end

    push!(spdxDoc.Packages, package)
    push!(builddata.packagesinsbom, uuid)
    return package.SPDXID
end

## Building an SPDX Package for a Julia artifact
function buildSPDXpackage!(spdxDoc::SpdxDocumentV2, artifact_name::AbstractString, artifact::Dict{String, Any}, builddata::spdxPackageData)
    git_tree_sha1= artifact["git-tree-sha1"]
    package= SpdxPackageV2("SPDXRef-$(git_tree_sha1)")

    # Check if this artifact already exists in the SBOM
    # TODO: Maybe add additional names to the name field? That would require searching for the package and then parsing
    (git_tree_sha1 in builddata.artifactsinsbom) && (return package.SPDXID)

    package.Name= artifact_name
    package.Supplier= SpdxCreatorV2("NOASSERTION")
    package.Originator= SpdxCreatorV2("NOASSERTION") # TODO: Should there be instructions like for packages?
    resolve_pkgsource!(package, artifact)
    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")
    push!(package.LicenseInfoFromFiles, SpdxLicenseExpressionV2("NOASSERTION"))
    package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION") 
    package.Copyright= "NOASSERTION"  # TODO:  Should there be instructions like for packages?  Scan license files for the first line that says "Copyright"?  That would about work.
    package.Summary= "This is a Julia artifact. \nAn artifact is a binary runtime or other data store not written in the Julia language that is used by a Julia package."
    if haskey(artifact, ["lazy"]) && artifact["lazy"] == true
        package.Summary*= "\nThis is a lazy artifact that is not downloaded when the parent Julia package is installed. It will be downloaded when needed."
    end

    package.Comment= "The SPDX ID field is derived from the Git tree hash of the artifact files which is used to uniquely identify it."

    push!(spdxDoc.Packages, package)
    push!(builddata.artifactsinsbom, git_tree_sha1)
    return package.SPDXID
end

function spdxpkgverifcode(source::AbstractString, packageInstructions::Union{Missing, spdxPackageInstructions})
    if ismissing(packageInstructions)
        packageInstructions= spdxPackageInstructions(name= "") # go with the defaults
    end

    excluded_files= copy(packageInstructions.excluded_files)
    ismissing(packageInstructions.spdxfile_toexclude) || append!(excluded_files, packageInstructions.spdxfile_toexclude)
    return ComputePackageVerificationCode(source, excluded_files, packageInstructions.excluded_dirs, packageInstructions.excluded_patterns)
end