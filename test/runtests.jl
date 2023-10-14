using Pkg
using PkgToSoftwareBOM
using SPDX
using Test
using UUIDs

@testset "PkgToSoftwareBOM.jl" begin
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
end
