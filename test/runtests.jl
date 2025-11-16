using Pkg
using PkgToSoftwareBOM
using Test
using UUIDs
using Base.BinaryPlatforms

@testset "PkgToSoftwareBOM.jl" begin
    # Function issetequal doesn't work with vectors of SpdxRelationshipV2
    #  SPDX needs to define a custom hash() function before issetequal will work. See Issue #38
    function isvectorsetequal(a::Vector, b::Vector)
        length(a) == length(b) || return false
        for v in a
            any(isequal.([v], b)) || return false
        end
        return true
    end

    # Add Test Registry
    Pkg.Registry.add(RegistrySpec(url= "https://github.com/SamuraiAku/DummyRegistry.jl.git"))

    @testset "README.md examples: Environment" begin

        ## Example #1
        sbom = generateSPDX(spdxCreationData(find_artifactsource= true))
        # The SBOM is too big and complex to check everything, but we can check some things
        root_relationships= filter(r -> r.RelationshipType=="DESCRIBES", sbom.Relationships)
        @test issetequal(getproperty.(root_relationships, :RelatedSPDXID), ["SPDXRef-PkgToSoftwareBOM-6254a0f9-6143-4104-aa2e-fd339a2830a6", "SPDXRef-SPDX-47358f48-d834-4249-91f5-f6185eb3d540", "SPDXRef-RegistryInstances-2792f1a3-b283-48e8-9a74-f99dce5104f3", "SPDXRef-Reexport-189a3867-3050-52da-a836-e630ba90ab69", "SPDXRef-LicenseCheck-726dbf0d-6eb6-41af-b36c-cd770e0f00cc"])
        @test !isempty(filter(p -> p.SPDXID == "SPDXRef-PkgToSoftwareBOM-6254a0f9-6143-4104-aa2e-fd339a2830a6", sbom.Packages))
        @test !isempty(filter(p -> p.SPDXID == "SPDXRef-SPDX-47358f48-d834-4249-91f5-f6185eb3d540", sbom.Packages))
        @test !isempty(filter(isequal(SpdxRelationshipV2("SPDXRef-SPDX-47358f48-d834-4249-91f5-f6185eb3d540 DEPENDENCY_OF SPDXRef-PkgToSoftwareBOM-6254a0f9-6143-4104-aa2e-fd339a2830a6")), sbom.Relationships))


        ## Example #2 + Check dual registries
        rootpackages = filter(p -> p.first in ["PkgToSoftwareBOM"],
                              Pkg.project().dependencies)
        sbom_with_exclusions = generateSPDX(spdxCreationData(; rootpackages), ["DummyRegistry", "General"])
        root_relationships= filter(r -> r.RelationshipType=="DESCRIBES", sbom_with_exclusions.Relationships)
        @test issetequal(getproperty.(root_relationships, :RelatedSPDXID), ["SPDXRef-PkgToSoftwareBOM-6254a0f9-6143-4104-aa2e-fd339a2830a6"])
        @test !isnothing(filter(p -> p.SPDXID == "SPDXRef-PkgToSoftwareBOM-6254a0f9-6143-4104-aa2e-fd339a2830a6", sbom.Packages))
        # Dummy Registry, which is checked first, has only an old version of DataStructures (0.17.20) whereas SPDX needs at least 0.18
        # Verify that the package in the SBOM did not choose that version for the SBOM
        DataStructuresPkg= filter(p-> occursin("SPDXRef-DataStructures", p.SPDXID), sbom.Packages)
        @test VersionNumber(DataStructuresPkg[1].Version) >= v"0.18"

        # Use the package server for downloads
        sbom_with_packageserver = generateSPDX(spdxCreationData(use_packageserver= true))
        package_tree_hash= sbom.Packages[end-1].DownloadLocation.VCS_Tag
        package_server_source= string(sbom_with_packageserver.Packages[end-1].DownloadLocation)
        packageserver= PkgToSoftwareBOM.pkg_server() # Internal function
        @test startswith(package_server_source, packageserver)
        @test endswith(package_server_source, package_tree_hash)

        # Try with a package server that doesn't exist
        ENV["JULIA_PKG_SERVER"]= "https://pkg.nowhere.org"
        sbom_with_packageserver = generateSPDX(spdxCreationData(use_packageserver= true))
        @test sbom.Packages[end-1].DownloadLocation == sbom_with_packageserver.Packages[end-1].DownloadLocation
        delete!(ENV, "JULIA_PKG_SERVER")
    end

    @testset "README.md examples: Developer" begin
        # So that we're working with a real package here, instead of "MyPackageName.jl" use "SPDX"
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

        root_relationships= filter(r -> r.RelationshipType=="DESCRIBES", sbom.Relationships)
        @test issetequal(getproperty.(root_relationships, :RelatedSPDXID), ["SPDXRef-SPDX-47358f48-d834-4249-91f5-f6185eb3d540"])
        @test !isempty(filter(p -> p.SPDXID == "SPDXRef-SPDX-47358f48-d834-4249-91f5-f6185eb3d540", sbom.Packages))

        @test sbom.Name == SPDX_docCreation.Name
        @test isvectorsetequal(sbom.CreationInfo.Creator, SPDX_docCreation.Creators)
        @test sbom.CreationInfo.CreatorComment == SPDX_docCreation.CreatorComment * string("\nTarget Platform: ", string(HostPlatform()))
        @test occursin(SPDX_docCreation.DocumentComment, sbom.DocumentComment)
        @test sbom.Namespace.URI == SPDX_docCreation.NamespaceURL

        SPDX_pkg= filter(p -> p.Name == myPackage_instr.name, sbom.Packages)[1]
        @test SPDX_pkg.Originator== myName
        @test SPDX_pkg.LicenseDeclared== myLicense
        @test SPDX_pkg.Copyright== myPackage_instr.copyright
        @test SPDX_pkg.Name== package_name
        @test SPDX_pkg.ExternalReferences[1].Category == "PACKAGE-MANAGER"
        @test SPDX_pkg.ExternalReferences[1].RefType == "purl"
        @test SPDX_pkg.ExternalReferences[1].Locator == "pkg:julia/$(SPDX_pkg.Name)@$(SPDX_pkg.Version)?uuid=47358f48-d834-4249-91f5-f6185eb3d540"
    end

    # Setup environment for the next tests
    envdir= mktempdir();
    envpaths= joinpath.(envdir, ["Project.toml", "Manifest.toml"])
    cp.(["./test_environment/Project.toml", "./test_environment/Manifest.toml"], envpaths)
    Pkg.activate(envdir)
    Pkg.resolve()
    Pkg.instantiate()

    @testset "Repo Track + Dual registries" begin
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
        @test sbom.CreationInfo.CreatorComment == string("Target Platform: ", string(HostPlatform()))
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
        @test all(isequal.(getproperty.(sbom.Packages, :LicenseInfoFromFiles), [[SpdxSimpleLicenseExpressionV2("MIT")]]))
        @test all(isequal.(getproperty.(sbom.Packages, :LicenseDeclared), [SpdxSimpleLicenseExpressionV2("MIT")]))
        @test all(ismissing.(getproperty.(sbom.Packages, :LicenseComments)))
        @test all(isequal.(getproperty.(sbom.Packages, :Copyright), "NOASSERTION"))
        @test all(isequal.(getproperty.(sbom.Packages, :Summary), "This is a Julia package, written in the Julia language."))
        @test all(ismissing.(getproperty.(sbom.Packages, :DetailedDescription)))
        @test all(isequal.(getproperty.(sbom.Packages, :Comment), "The SPDX ID field is derived from the UUID that all Julia packages are assigned by their developer to uniquely identify it."))
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
            "Dummy1" => (Version= "1.0.1", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy1.git@008576972fec29599db48c93f85350c4a266c877"), HomePage= "https://github.com/SamuraiAku/Dummy1.git")
            "Dummy2" => (Version= "1.0.1", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy2.git@322507efe9c377be703d1788305e481cfd0b9be7"), HomePage= "https://github.com/SamuraiAku/Dummy2.git")
            "Dummy3" => (Version= "1.0.0", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy3.git@c45b219b60c32061a31194f5093610aab3d3bd93"), HomePage= "https://github.com/SamuraiAku/Dummy3.git")
            "Dummy4" => (Version= "1.0.0", DownloadLocation= SpdxDownloadLocationV2("git+https://github.com/SamuraiAku/Dummy4.git@v1.0.0"), HomePage= "https://github.com/SamuraiAku/Dummy4.git")
        ]
        for p in package_info
            idx= findfirst(isequal(p.first), getproperty.(sbom.Packages, :Name))
            @test sbom.Packages[idx].Version == p.second.Version
            @test sbom.Packages[idx].DownloadLocation == p.second.DownloadLocation
            @test sbom.Packages[idx].HomePage == p.second.HomePage
        end

        ## Regenerate the SBOM trying to use the package server. Since none of these packages are in the pacage server
         # the download locations should be unchanged
        sbom2= generateSPDX(spdxCreationData(rootpackages= filter(p-> (p.first in ["Dummy4"]), Pkg.project().dependencies), use_packageserver= true), ["DummyRegistry", "General"]);
        @test issetequal(sbom.Packages, sbom2.Packages)
    end

    @testset "Artifact Tests" begin
        using MWETestSBOM_LazyArtifact
        spdxid= "SPDXRef-MWETestSBOM_LazyArtifact-1c66bc15-73f4-4e94-8c80-c77ca7b88078"

        download_artifact()
        sbom_downloaded= generateSPDX(spdxCreationData(rootpackages= filter(p-> (p.first in ["MWETestSBOM_LazyArtifact"]), Pkg.project().dependencies)), ["DummyRegistry", "General"]);
        
        remove_artifact()
        sbom_lazy= generateSPDX(spdxCreationData(rootpackages= filter(p-> (p.first in ["MWETestSBOM_LazyArtifact"]), Pkg.project().dependencies)), ["DummyRegistry", "General"]);

        # The two SBOMS should be almost identical, except that with sbom_lazy you can't compute the verification code
        ## Check the document properties I know have to be identical
        @test SPDX.compare_b(sbom_downloaded, sbom_lazy; skipproperties= [:Namespace, :CreationInfo, :Packages])
        ## Compare the Packages, excluding the verification code
        ### If I update the test artifact later to have a license file, that will be another difference.
        @test SPDX.compare_b(sbom_downloaded.Packages, sbom_lazy.Packages; skipproperties= [:VerificationCode])
        ## Compare the Package verification codes
        
        # TODO: A testset for a JLL
    end

    # Remove registry
    Pkg.Registry.rm("DummyRegistry")
end
