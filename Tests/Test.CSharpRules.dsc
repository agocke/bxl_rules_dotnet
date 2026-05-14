// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import * as CSharp from "Sdk.Rules.CSharp";
import * as Rules from "Sdk.Rules";
import {Cmd} from "Sdk.Transformers";

const dotnetSdk = importFrom("DotNetSdk").extracted;
const targetFramework = "net10.0";
const runtimeVersion = "10.0.5";
const sdkVersion = "10.0.201";

const toolchain = CSharp.csharpToolchainFromDotNetSdk({
    name: "downloaded-dotnet-sdk",
    contents: dotnetSdk,
    sdkVersion: sdkVersion,
});

const systemRuntime = dotnetSdk.assertExistence(
    r`packs/Microsoft.NETCore.App.Ref/${runtimeVersion}/ref/${targetFramework}/System.Runtime.dll`
);

const systemIoFileSystem = dotnetSdk.assertExistence(
    r`packs/Microsoft.NETCore.App.Ref/${runtimeVersion}/ref/${targetFramework}/System.IO.FileSystem.dll`
);

function test_sdkToolchain_buildsLibraryGraph(): string {
    const lib = CSharp.csharp_library({
        name: "ToolchainSmokeTest",
        toolchain: toolchain,
        srcs: ["src/TestLib.cs"],
        refs: [CSharp.fileLabel(systemRuntime)],
    });

    Contract.assert(lib !== undefined, "csharp_library must return a provider");
    Contract.assert(lib.binary !== undefined, "csharp_library must surface the compiled binary");
    Contract.assert(lib.refs.length === 1, "expected the direct ref to be preserved");
    Contract.assert(lib.defaultInfo.files.length === 1, "DefaultInfo.files must contain the binary");
    Contract.assert(lib.defaultInfo.runfiles !== undefined, "runfiles should be populated");
    Contract.assert(lib.defaultInfo.runfiles.length >= 2, "runfiles should include the binary and direct refs");
    Contract.assert(toolchain.compilerPayload !== undefined, "toolchain helper should surface the Roslyn payload files");
    Contract.assert(toolchain.compilerPayload.length > 1, "Roslyn payload should contain csc sidecar files");

    return "ok";
}

interface RunManagedBinaryAttrs {
    name: string;
    binary: CSharp.CSharpInfo;
    toolchain: CSharp.CSharpToolchain;
}

interface RunManagedBinaryResult extends Rules.DefaultInfo {
    outputFile: File;
}

function runManagedBinary(args: RunManagedBinaryAttrs): RunManagedBinaryResult {
    return Rules.rule<RunManagedBinaryAttrs, RunManagedBinaryAttrs, CSharp.CSharpToolchain, RunManagedBinaryResult>({
        doc: "Run a managed binary with dotnet exec and capture its output file.",
        toolchain: args.toolchain,
        resolve: (attrs, _resolver) => attrs,
        impl: (ctx) => {
            const runtimeConfig = ctx.actions.writeFile(
                ctx.actions.declareOutput(ctx.args.name + ".runtimeconfig.json"),
                [
                    "{",
                    "  \"runtimeOptions\": {",
                    `    \"tfm\": \"${targetFramework}\",`,
                    "    \"framework\": {",
                    "      \"name\": \"Microsoft.NETCore.App\",",
                    `      \"version\": \"${runtimeVersion}\"`,
                    "    }",
                    "  }",
                    "}",
                ]
            );

            const output = ctx.actions.declareOutput("binary-integration-output.txt");
            const produced = ctx.actions.run({
                tool: ctx.toolchain.hostExe,
                arguments: [
                    Cmd.argument("exec"),
                    Cmd.argument("--runtimeconfig"),
                    Cmd.argument(Rules.cmdInput(runtimeConfig)),
                    Cmd.argument(Rules.cmdInput(Rules.sourceArtifact(ctx.args.binary.binary))),
                    Cmd.argument(Rules.cmdOutput(output)),
                ],
                outputs: [output],
                description: `run managed binary: ${ctx.args.name}`,
            });

            const outputFile = Rules.getFile(produced[0]);
            return {
                kind: "DefaultInfo",
                files: [outputFile],
                outputFile: outputFile,
            };
        },
    })(args);
}

function test_sdkToolchain_buildsAndRunsBinary(): string {
    const app = CSharp.csharp_binary({
        name: "ToolchainBinarySmokeTest",
        toolchain: toolchain,
        srcs: ["src/TestProgram.cs"],
        refs: [CSharp.fileLabel(systemRuntime), CSharp.fileLabel(systemIoFileSystem)],
    });

    const result = runManagedBinary({
        name: "ToolchainBinaryRun",
        binary: app,
        toolchain: toolchain,
    });

    Contract.assert(app.binary !== undefined, "csharp_binary must surface the compiled binary");
    Contract.assert(result.outputFile !== undefined, "running the binary must surface the captured output file");

    return "ok";
}

@@public export const r01 = test_sdkToolchain_buildsLibraryGraph();
@@public export const r02 = test_sdkToolchain_buildsAndRunsBinary();
