using Pkg
using PkgToSoftwareBOM
using SPDX
using Test
using UUIDs

@testset "PkgToSoftwareBOM.jl" begin
    # Add Test Registry
    Pkg.Registry.add(RegistrySpec(url= "https://github.com/SamuraiAku/DummyRegistry.jl.git"))

    testdir= mktempdir()
    @testset "README.md examples: Environment" begin
        sbom = generateSPDX()
        path = joinpath(testdir , "myEnvironmentSBOM.spdx.json")
        writespdx(sbom, path)
        rt_sbom = readspdx(path)

        # Roundtripping isn't exact---extra lines are trimmed from the DocumentComment,
        # and the relationships order seems to be nondeterministic
        # For now, test the components separately:
        @test SPDX.compare(rt_sbom, sbom; skipproperties=[:DocumentComment, :Relationships]).bval
        @test isequal(sbom.DocumentComment[1:(end - 3)], rt_sbom.DocumentComment)

        # ...not actually sure how/why this is broken, but it seems to be (when
        # run via testharness)
        @test_broken issetequal(sbom.Relationships, rt_sbom.Relationships)

        rootpackages = filter(p -> !(p.first in ["PkgToSoftwareBOM", "SPDX"]),
                              Pkg.project().dependencies)
        sbom_with_exclusions = generateSPDX(spdxCreationData(; rootpackages))
        path2 = joinpath(testdir,  "myEnvironmentSBOM.spdx.json")
        writespdx(sbom_with_exclusions, path2)
        rt_sbom_with_exclusions = readspdx(path2)

        @test SPDX.compare(rt_sbom_with_exclusions, sbom_with_exclusions;
                           skipproperties=[:DocumentComment]).bval
        @test isequal(sbom_with_exclusions.DocumentComment[1:(end - 3)],
                      rt_sbom_with_exclusions.DocumentComment)
    end

    @testset "README.md examples: Developer" begin
        # So that we're working with a real package here, instead of "MyPackageName.jl" use "SPDX.jl"
        package_name = "SPDX"

        myName = SpdxCreatorV2("Person", "John Doe", "email@loopback.com")
        myOrg = SpdxCreatorV2("Organization", "Open-Source Org", "email2@loopback.com")
        myTool = SpdxCreatorV2("Tool", "PkgToSoftwareBOM.jl", "")
        devRoot = filter(p -> p.first == package_name, Pkg.project().dependencies)
        myLicense = SpdxLicenseExpressionV2("MIT")

        myPackage_instr = spdxPackageInstructions(;
                                                  spdxfile_toexclude=["MyPackageName.spdx.json"],
                                                  originator=myName,
                                                  declaredLicense=myLicense,
                                                  copyright="Copyright (c) 2022 John Doe <email@loopback.com> and contributors",
                                                  name=package_name)
        myNamespace = "https://github.com/myUserName/myPackage.jl/myPackage.spdx.json"

        active_pkgs = Pkg.project().dependencies
        SPDX_docCreation = spdxCreationData(; Name="MyPackageName.jl Developer SBOM",
                                            Creators=[myName, myOrg, myTool],
                                            CreatorComment="Optional field for general comments about the creation of the SPDX document",
                                            DocumentComment="Optional field for to provide comments to the consumers of the SPDX document",
                                            NamespaceURL=myNamespace,
                                            rootpackages=devRoot,
                                            packageInstructions=Dict{UUID,
                                                                     spdxPackageInstructions}(active_pkgs[myPackage_instr.name] => myPackage_instr))

        sbom = generateSPDX(SPDX_docCreation)
        path = joinpath(testdir, "myEnvironmentSBOM.spdx.json")
        writespdx(sbom, path)
        rt_sbom = readspdx(path)
        @test SPDX.compare(rt_sbom, sbom; skipproperties=[:DocumentComment]).bval
        @test isequal(sbom.DocumentComment[1:(end - 3)], rt_sbom.DocumentComment)
    end

    @testset "Repo Track + Dual registries" begin
        function isvectorsetequal(a::Vector, b::Vector)
            length(a) == length(b) || return false
            for v in a
                any(isequal.([v], b)) || return false
            end
            return true
        end

        Pkg.activate("./test_environment")
        Pkg.instantiate()
        Pkg.instantiate
        sbom= generateSPDX(spdxCreationData(rootpackages= filter(p-> (p.first in ["Dummy4"]), Pkg.project().dependencies)), ["DummyRegistry", "General"]);
        # Dummy4 and all its dependencies were created by the author for testing purposes. They have no functional code, just the dependencies
        # Therefore we know exactly what the SBOM should look like and can test for this.
        # Dummy4 is accessed by directly adding its repository, Dummy1-3 are registered in the registry DummyRegistry, also created by the author
        dummy1_spdxid= "SPDXRef-Dummy1-f7bc0a32-b501-410f-a5e3-5d2b3b8c0e6f"
        dummy2_spdxid= "SPDXRef-Dummy2-fb23cc6c-415b-4b10-a7ae-91d1f24ce4a7"
        dummy3_spdxid= "SPDXRef-Dummy3-a15f9a99-31c9-401d-87e4-3fe0ccb07a31"
        dummy4_spdxid= "SPDXRef-Dummy4-bd21c0da-0f63-47d8-a8d0-2a7f3678fd80"
        
        expected_relationships= [
            SpdxRelationshipV2("SPDXRef-DOCUMENT",  "DESCRIBES",  dummy4_spdxid),
            SpdxRelationshipV2(dummy1_spdxid,  "DEPENDENCY_OF",  dummy4_spdxid),
            SpdxRelationshipV2(dummy3_spdxid,  "DEPENDENCY_OF",  dummy1_spdxid),
            SpdxRelationshipV2(dummy2_spdxid,  "DEPENDENCY_OF",  dummy1_spdxid),
            SpdxRelationshipV2(dummy3_spdxid,  "DEPENDENCY_OF",  dummy2_spdxid)
        ]

        #### Check the document fields
        @test sbom.Version == "SPDX-2.3"
        @test sbom.DataLicense == SpdxSimpleLicenseExpressionV2("CC0-1.0")
        @test sbom.SPDXID == "SPDXRef-DOCUMENT"
        @test sbom.Name== "Julia Environment"
        @test sbom.Namespace.URI == "https://spdx.org/spdxdocs/Julia_Environment" && !isnothing(sbom.Namespace.UUID)
        @test isempty(sbom.ExternalDocReferences)
        @test ismissing(sbom.CreationInfo.LicenseListVersion)
        @test length(sbom.CreationInfo.Creator) == 1 && sbom.CreationInfo.Creator[1] == SpdxCreatorV2("Tool: PkgToSoftwareBOM.jl")
        @test !ismissing(sbom.CreationInfo.Created)
        @test ismissing(sbom.CreationInfo.CreatorComment)
        @test occursin("DummyRegistry", sbom.DocumentComment) && occursin("General registry", sbom.DocumentComment)
        @test isempty(sbom.Files)
        @test isempty(sbom.Snippets)
        @test isempty(sbom.LicenseInfo)
        @test isvectorsetequal(expected_relationships, sbom.Relationships)
        @test isempty(sbom.Annotations)

        #### Check the packages
        # See if the packages expected are present
        pkg_spdxids= getproperty.(sbom.Packages, :SPDXID)
        @test length(sbom.Packages) == 4 && issetequal(pkg_spdxids, [dummy1_spdxid, dummy2_spdxid, dummy3_spdxid, dummy4_spdxid])

        # First, test all the fields that are the same
        @test all(ismissing.(getproperty.(sbom.Packages, :FileName)))
        @test all(isequal.(getproperty.(sbom.Packages, :Supplier), [SpdxCreatorV2("NOASSERTION")]))
        @test all(isequal.(getproperty.(sbom.Packages, :Originator), [SpdxCreatorV2("NOASSERTION")]))
        @test all(getproperty.(sbom.Packages, :FilesAnalyzed))
        @test all(isempty.(getproperty.(sbom.Packages, :Checksums)))
        @test all(isequal.(getproperty.(sbom.Packages, :LicenseConcluded), [SpdxSimpleLicenseExpressionV2("NOASSERTION")]))
        @test all(isequal.(getproperty.(sbom.Packages, :LicenseInfoFromFiles), [[SpdxSimpleLicenseExpressionV2("NOASSERTION")]]))
        @test all(isequal.(getproperty.(sbom.Packages, :LicenseDeclared), [SpdxSimpleLicenseExpressionV2("NOASSERTION")]))
        @test all(ismissing.(getproperty.(sbom.Packages, :LicenseComments)))
        @test all(isequal.(getproperty.(sbom.Packages, :Copyright), "NOASSERTION"))
        @test all(ismissing.(getproperty.(sbom.Packages, :Summary)))
        @test all(ismissing.(getproperty.(sbom.Packages, :DetailedDescription)))
        @test all(isequal.(getproperty.(sbom.Packages, :Comment), "The SPDX ID field is derived from the UUID that all Julia packages are assigned by their developer to uniquely identify it."))
        @test all(isempty.(getproperty.(sbom.Packages, :ExternalReferences)))
        @test all(isempty.(getproperty.(sbom.Packages, :Attributions)))
        @test all(ismissing.(getproperty.(sbom.Packages, :PrimaryPurpose)))
        @test all(ismissing.(getproperty.(sbom.Packages, :ReleaseDate)))
        @test all(ismissing.(getproperty.(sbom.Packages, :BuiltDate)))
        @test all(ismissing.(getproperty.(sbom.Packages, :ValidUntilDate)))
        @test all(isempty.(getproperty.(sbom.Packages, :Annotations)))

        # Test the fields that are different.  All the differences involve the package name
        #  Find the index by SPDXID, then use the index to check all the other fields
        #  (Name, Version, DownloadLocation, VerificationCode, HomePage)
        @test issetequal(getproperty.(sbom.Packages, :Name), ["Dummy1", "Dummy2", "Dummy3", "Dummy4"])
        @test all(.!(ismissing.(getproperty.(sbom.Packages, :VerificationCode))))
        # Given a key of the name of SPDXID, you know the value of Version, DownloadLocation and Homepage
        # Loop, on the names then find the index that has that name
        package_info= [
            "Dummy1" => (Version= "1.0.1", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy1.git@v1.0.1"), HomePage= "https://github.com/SamuraiAku/Dummy1.git")
            "Dummy2" => (Version= "1.0.1", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy2.git@v1.0.1"), HomePage= "https://github.com/SamuraiAku/Dummy2.git")
            "Dummy3" => (Version= "1.0.0", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy3.git@v1.0.0"), HomePage= "https://github.com/SamuraiAku/Dummy3.git")
            "Dummy4" => (Version= "1.0.0", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy4.git@main"), HomePage= "https://github.com/SamuraiAku/Dummy4.git")
        ]
        for p in package_info
            idx= findfirst(isequal(p.first), getproperty.(sbom.Packages, :Name))
            @test sbom.Packages[idx].Version == p.second.Version
            @test sbom.Packages[idx].DownloadLocation == p.second.DownloadLocation
            @test sbom.Packages[idx].HomePage == p.second.HomePage
        end
    end

    # Remove registry
    Pkg.Registry.rm("DummyRegistry")
end
