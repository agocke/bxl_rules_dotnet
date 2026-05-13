// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import * as CSharp from "Sdk.Rules.CSharp";

const dotnetSdk = importFrom("DotNetSdk").extracted;

const toolchain = CSharp.csharpToolchainFromContents({
    name: "downloaded-dotnet-sdk",
    contents: dotnetSdk,
    hostPath: "dotnet",
    compilerPath: "sdk/10.0.201/Roslyn/bincore/csc.dll",
});

const systemRuntime = dotnetSdk.assertExistence(
    r`packs/Microsoft.NETCore.App.Ref/10.0.5/ref/net10.0/System.Runtime.dll`
);

function test_explicitToolchain_buildsLibraryGraph(): string {
    const lib = CSharp.csharp_library({
        name: "ToolchainSmokeTest",
        toolchain: toolchain,
        srcs: ["src/TestLib.cs"],
        fileRefs: [systemRuntime],
    });

    Contract.assert(lib !== undefined, "csharp_library must return a provider");
    Contract.assert(lib.binary !== undefined, "csharp_library must surface the compiled binary");
    Contract.assert(lib.refs.length === 1, "expected the direct fileRef to be preserved");
    Contract.assert(lib.defaultInfo.files.length === 1, "DefaultInfo.files must contain the binary");
    Contract.assert(lib.defaultInfo.runfiles !== undefined, "runfiles should be populated");
    Contract.assert(lib.defaultInfo.runfiles.length >= 2, "runfiles should include the binary and direct refs");

    return "ok";
}

@@public export const r01 = test_explicitToolchain_buildsLibraryGraph();
