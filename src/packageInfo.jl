# SPDX-License-Identifier: MIT

###############################
function resolve_pkgsource!(uuid::UUID, package::SpdxPackageV2, packagedata::Pkg.API.PackageInfo, registrydata::Union{Nothing, Missing, PackageRegistryInfo})
    # The location of the SPDX package's source code depend on whether Pkg is tracking the package via:
    #   1) A package listed in the registry; Some stdlibs are tracked in the General registry, some are not.
    #   2) Connecting directly with a git repository
    #   3) Source code on a locally accessible storage device (i.e. no source control)
    #   4) A stdlib that is not tracked in the registry
    #   5) Is the locally stored code actually a registered package or code from a repository that is under development?

    if packagedata.is_tracking_registry && !isnothing(registrydata) && !ismissing(registrydata)
        # Simplest and most common case is if you are tracking a registered package
        # stdlibs that aren't actually in the registry tend to lie and say they are tracking, hence the additional checks
        repo_download= SpdxDownloadLocationV2("git+$(registrydata.packageURL)@$(registrydata.packageTreeHash)$(isempty(registrydata.packageSubdir) ? "" : "#"*registrydata.packageSubdir)")
        
        if is_stdlib(uuid)
            package.SourceInfo= "This package is part of the Julia standard library.\n"
        end

        if isnothing(registrydata.packageserverURL)
            package.DownloadLocation= repo_download
            package.SourceInfo= package.SourceInfo * "Download Location is supplied by the $(registrydata.registryName) registry:\n$(registrydata.registryURL)"
            package.SourceInfo= package.SourceInfo * "\nThe hash supplied in Download Location is not the typical git commit hash. Instead it is a git tree hash. The easiest way to retrieve this version from the cloned repository is to use the command:\ngit archive --output=path/to/archive.tar <tree hash>"
            package.Supplier= SpdxCreatorV2("NOASSERTION")
        else
            package.DownloadLocation= SpdxDownloadLocationV2(registrydata.packageserverURL)
            if startswith(registrydata.packageserverURL, "https://pkg.julialang.org/")
                package.Supplier= SpdxCreatorV2("Organization", "JuliaLang", "")
            else
                package.Supplier= SpdxCreatorV2("NOASSERTION")
            end
            package.SourceInfo= package.SourceInfo * "Download is a compressed tarball, supplied from a package server, rather than the package source respository."
        end

        if is_stdlib(uuid)
            package.HomePage= "https://julialang.org"
            package.Supplier= SpdxCreatorV2("Organization", "JuliaLang", "")
        else
            package.HomePage= registrydata.packageURL
        end
    elseif packagedata.is_tracking_repo
        # Next simplest case is if you are directly tracking a repository
        # TODO: Extract the subdirectory information if it exists. Can't find it in packagedata.
        package.DownloadLocation= SpdxDownloadLocationV2("git+$(packagedata.git_source)@$(packagedata.git_revision)")
        package.HomePage= packagedata.git_source
        package.SourceInfo= "$(packagedata.name) is directly tracking a git repository."
        package.Supplier= SpdxCreatorV2("NOASSERTION")
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
        package.Supplier= SpdxCreatorV2("NOASSERTION")
    elseif is_stdlib(uuid) # That's not being tracked in a registry
        package.DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/JuliaLang/julia.git@v$(string(VERSION))#stdlib/$(package.Name)")
        package.SourceInfo= "This package is part of the Julia standard library and is located in the Julia source code tree."
        package.HomePage= "https://julialang.org"
        package.Supplier= SpdxCreatorV2("Organization", "JuliaLang", "")
    elseif packagedata.is_tracking_registry && ismissing(registrydata)
        error("Package $(packagedata.name) and/or its version cannot be found in the specified registries.\nPlease review the installed registries with Pkg and the value of parameter \'sbomRegistries\' when the function \'generateSPDX\' is called")
    else
        # This should not happen unless there has been a breaking change in Pkg
        error("PkgToSBOM.resolve_pkgsource!():  Unable to resolve source information for $(packagedata.name). Maybe the Pkg source has changed in a breaking way?")
    end

    return nothing
end

###############################
function resolve_pkgsource!(package::SpdxPackageV2, artifact::Dict{String, Any})
    platform_keys= setdiff(keys(artifact), Set(["download", "git-tree-sha1", "lazy"]))
    if length(platform_keys) > 0
        package.SourceInfo= ""
        package.SourceInfo= string(package.SourceInfo, "The artifact download URL was determined using the following platform specific parameters:")
        for k in platform_keys
            package.SourceInfo= string(package.SourceInfo, "\n", k * ": ", artifact[k])
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
            else
                package.SourceInfo= package.SourceInfo * "\n"
            end
            package.SourceInfo= string(package.SourceInfo, "This artifact may also be downloaded from the following alternate locations:")
            for dl in artifact["download"][2:end]
                package.SourceInfo= string(package.SourceInfo, "\n", "PackageDownloadLocation: $(dl["url"])")
                package.SourceInfo= string(package.SourceInfo, "\n", "PackageChecksum: SHA256: $(dl["sha256"])")
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
    package.Supplier= SpdxCreatorV2("NOASSERTION")

    return nothing
end

###############################
function resolve_pkglicense!(package::SpdxPackageV2, packagepath::AbstractString, packageInstructions, licenseScan::Bool)
    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")

    if ismissing(packageInstructions) 
        if false == licenseScan
            package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
            @logmsg Logging.LogLevel(-50) "License scanning has been disabled"
        else    
            scanresults= scan_for_licenses(packagepath) # Returns an array of found license files in top level of packagepath with scanner results
            if isempty(scanresults)
                package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
                @logmsg Logging.LogLevel(-50) "Cannot locate a license file"
            else
                # If multiple licenses exist, pick the first one as declared and log the rest
                # As long as it exists at the top of the pkg
                if splitdir(scanresults[1].license_filename)[1] == packagepath
                    package.LicenseDeclared= SpdxLicenseExpressionV2(scanresults[1].licenses_found[1])
                    @logmsg Logging.LogLevel(-50) "Declared License:" LicenseDeclared= package.LicenseDeclared LicenseFile= scanresults[1].license_filename
                else
                    package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
                    @logmsg Logging.LogLevel(-50) "Declared License cannot be determined"
                end
                package.LicenseInfoFromFiles= [SpdxLicenseExpressionV2(license) for f in scanresults for license in f.licenses_found]
                @logmsg Logging.LogLevel(-75) "License data found in:" licenselist= [(a.license_filename, a.licenses_found) for a in scanresults]
                package.LicenseInfoFromFiles= unique(package.LicenseInfoFromFiles) # Remove duplicates
            end
        end
    else
        package.LicenseDeclared= packageInstructions.declaredLicense
    end
end

###############################
function resolve_jllsource(artifactpackage::SpdxPackageV2, artifact_wrapperdata::Pkg.API.PackageInfo)
    # Only JLLs using Yggdrasil, the Julia community build tree, have a known build pattern that we can grep
    # through to find the necessary information
    startswith(artifactpackage.DownloadLocation.HostPath, "github.com/JuliaBinaryWrappers/") || return nothing
    
    # The link to the artifact source can be found in the README.md file of the JLL
    # Read through it line by line to find the golden phrase and links
    markdownlink_regex= r"originating \[(.*?)\]\((\S*?) ?('(.*?)')?\) script can be found on \[(.*?)\]\((\S*?) ?('(.*?)')?\), the community build tree"  # markdown link extraction pattern from https://regex101.com/library/fTJqF7?orderBy=RELEVANCE&search=markdown+link
    url_regex= r"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?"  # From Appendix B of RFC 3986
    Yggdrasil_regex= r"/JuliaPackaging/Yggdrasil/blob/(?<Hash>[[:xdigit:]]{40})(?<Path>[[:graph:]]*)build_tarballs.jl"  # extract the githash, and the path after the hash
    
    readme= string(artifact_wrapperdata.source, "/README.md")
    isfile(readme) || return nothing
    sourceinfo= open(readme) do io
        while !eof(io)
            build_tarballs_search= match(markdownlink_regex, readline(io))
            isnothing(build_tarballs_search) && continue

            # Make sure that this readme line has the expected format
            build_tarballs_search[1] == "`build_tarballs.jl`" || return nothing
            build_tarballs_search[5] == "`Yggdrasil`" || return nothing
            build_tarballs_search[6] == "https://github.com/JuliaPackaging/Yggdrasil/" || return nothing

            URLparse= match(url_regex, build_tarballs_search[2])
            Yggdrasil_extract= match(Yggdrasil_regex, URLparse[5])
            return (githash= Yggdrasil_extract[1], path= Yggdrasil_extract[2])
        end
        return nothing
    end

    isnothing(sourceinfo) && return nothing

    buildrepo= "git+https://github.com/JuliaPackaging/Yggdrasil.git"*"@$(sourceinfo.githash)"*"#$(sourceinfo.path)"
    DownloadLocation= SpdxDownloadLocationV2(buildrepo)

    return DownloadLocation
end

###############################
function resolve_pkglicense!(package::SpdxPackageV2, artifact::Dict{String, Any}, licenseScan::Bool)
    package.LicenseConcluded= SpdxLicenseExpressionV2("NOASSERTION")
    artifact_src= artifact_path(Base.SHA1(artifact["git-tree-sha1"]))

    if false == licenseScan
        package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
        @logmsg Logging.LogLevel(-50) "License scanning has been disabled"
    elseif isdir(artifact_src)
        scanresults= scan_for_licenses(artifact_src)
        if isempty(scanresults)
            package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
            @logmsg Logging.LogLevel(-50) "Cannot locate a license file"
        else
            # If multiple licenses exist, pick the first one at the top or the first one in the share/licenses directory
            declared_licenses= filter(lic -> contains(splitdir(lic.license_filename)[1], joinpath(artifact_src, "share", "licenses"))
                                             || (splitdir(lic.license_filename)[1] == artifact_src)
                                    ,scanresults)
            if isempty(declared_licenses)
                package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
                @logmsg Logging.LogLevel(-50) "Declared License cannot be determined"
            else
                package.LicenseDeclared= SpdxLicenseExpressionV2(declared_licenses[1].licenses_found[1])
                @logmsg Logging.LogLevel(-50) "Declared License:" LicenseDeclared= package.LicenseDeclared LicenseFile= declared_licenses[1].license_filename
            end
            package.LicenseInfoFromFiles= [SpdxLicenseExpressionV2(license) for f in scanresults for license in f.licenses_found]
            @logmsg Logging.LogLevel(-75) "License data found in:" licenselist= [(a.license_filename, a.licenses_found) for a in scanresults]
            package.LicenseInfoFromFiles= unique(package.LicenseInfoFromFiles) # Remove duplicates
        end
    else 
        # Likely this is a lazy artifact that didn't get downloaded
        package.LicenseDeclared= SpdxLicenseExpressionV2("NOASSERTION")
        @logmsg Logging.LogLevel(-50) "Declared License cannot be determined. Likely a lazy artifact"
    end
end

###############################
function scan_for_licenses(dir::AbstractString)
    licenses_list= Vector{NamedTuple{(:license_filename, :licenses_found, :license_file_percent_covered), Tuple{String, Vector{String}, Float64}}}()
    for dirdata in walkdir(dir)
        root= dirdata[1]
        files= dirdata[3]
        files= [f for f in files if isfile(joinpath(root, f))]  # Remove anything that isn't an actual file, i.e. a broken symlink or symlinks to directories
        licenses_found= find_licenses_by_bruteforce(root; files=files)
        
        # If not empty, rebuild the licenses_found list with the complete path
        licenses_fullpath= typeof(licenses_list)()
        for lic in licenses_found
            push!(licenses_fullpath, (license_filename= joinpath(root, lic.license_filename), licenses_found= lic.licenses_found, license_file_percent_covered= lic.license_file_percent_covered))
        end

        licenses_list= isempty(licenses_fullpath) ? licenses_list : vcat(licenses_list, licenses_fullpath)
    end

    return licenses_list
end