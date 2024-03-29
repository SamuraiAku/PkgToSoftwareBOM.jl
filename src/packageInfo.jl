# SPDX-License-Identifier: MIT

function resolve_pkgsource!(package::SpdxPackageV2, packagedata::Pkg.API.PackageInfo, registrydata::Union{Nothing, Missing, PackageRegistryInfo})
    # The location of the SPDX package's source code depend on whether Pkg is tracking the package via:
    #   1) A package registry
    #   2) Connecting directly with a git repository
    #   3) Source code on a locally accessible storage device (i.e. no source control)
    #   4) Is the locally stored code actually a registered package or code from a repository that is under development?

    if packagedata.is_tracking_registry
        # Simplest and most common case is if you are tracking a registered package
        package.DownloadLocation= SpdxDownloadLocationV2("git+$(registrydata.packageURL)@v$(packagedata.version)$(isempty(registrydata.packageSubdir) ? "" : "#"*registrydata.packageSubdir)")
        package.HomePage= registrydata.packageURL
        package.SourceInfo= "Source Code Location is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)"
    elseif packagedata.is_tracking_repo
        # Next simplest case is if you are directly tracking a repository
        # TODO: Extract the subdirectory information if it exists. Can't find it in packagedata.
        package.DownloadLocation= SpdxDownloadLocationV2("git+$(packagedata.git_source)@$(packagedata.git_revision)")
        package.HomePage= packagedata.git_source
        package.SourceInfo= "$(packagedata.name) is directly tracking a git repository."
    elseif packagedata.is_tracking_path
        # The hard case is if you are working off a local file path.  Is it really just a path, or are you dev'ing a package?
        if registrydata isa PackageRegistryInfo
            # Then this must be a registered package under development
            package.DownloadLocation= SpdxDownloadLocationV2("git+$(registrydata.packageURL)@v$(packagedata.version)$(isempty(registrydata.packageSubdir) ? "" : "#"*registrydata.packageSubdir)")
            package.HomePage= registrydata.packageURL
            package.SourceInfo= "Source Code Location is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)"
            # TODO: See if this version exists in the registry. If it already does, then that's an error/warning on this dev version
            # TODO: Think of some additional note to source info to note this was made for a package under development?
        else
            # TODO: This may be a dev'ed version of a direct track from a repository. Figure out how to determine that
            #        Until then......
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


function resolve_pkgsource!(package::SpdxPackageV2, artifact::Dict{String, Any})
    platform_keys= setdiff(keys(artifact), Set(["download", "git-tree-sha1", "lazy"]))
    if length(platform_keys) > 0
        package.SourceInfo= ""
        package.SourceInfo= string(package.SourceInfo, "The artifact download URL was determined using the following platform specific parameters:", "\n")
        for k in platform_keys
            package.SourceInfo= string(package.SourceInfo, k * ": ", artifact[k], "\n")
        end
    end
    
    if haskey(artifact, "download") && !isempty(artifact["download"])
        # If there are multiple download locations specified, take the first one.
        package.DownloadLocation= SpdxDownloadLocationV2(artifact["download"][1]["url"])
        push!(package.Checksums, SpdxChecksumV2("SHA256", artifact["download"][1]["sha256"]))

        # Record alternative download locations
        if length(artifact["download"]) > 1
            if ismissing(package.SourceInfo)
                package.SourceInfo= ""
            end
            package.SourceInfo= string(package.SourceInfo, "This artifact may also be downloaded from the following alternate locations:", "\n")
            for dl in artifact["download"][2:end]
                package.SourceInfo= string(package.SourceInfo, "PackageDownloadLocation: $(dl["url"])", "\n")
                package.SourceInfo= string(package.SourceInfo, "PackageChecksum: SHA256: $(dl["sha256"])", "\n")
            end
        end
    end

    artifact_src= artifact_path(Base.SHA1(artifact["git-tree-sha1"]))
    if isdir(artifact_src) # Just in case this is a lazy artifact that didn't get downloaded
        package.VerificationCode= spdxpkgverifcode(artifact_src, missing)
    else
        @info "Verification code for artifact $(package.Name) not computed because directory does not exist. Probably a lazy artifact" artifact_src= artifact_src
    end


    package.HomePage= "NOASSERTION"

    return nothing
end