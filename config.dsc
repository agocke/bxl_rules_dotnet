// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

/**
 * Workspace config for validating bxl_rules_dotnet against externally
 * acquired dependencies.
 *
 * The test workspace pulls:
 *   - Sdk.Rules from agocke/bxl_rules via GitRepository
 *   - a .NET SDK archive via Download
 *   - this repo's local modules + tests via DScript
 */

config({
    resolvers: [
        {
            kind: "GitRepository",
            repositories: [{
                moduleName: "bxl_rules_repo",
                owner: "agocke",
                repository: "bxl_rules",
                commit: "6d141ed04aafb5d021b219d8de127f4d929d72ca",
            }],
        },
        {
            kind: "Download",
            downloads: [{
                moduleName: "DotNetSdk",
                url: "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.201/dotnet-sdk-10.0.201-linux-x64.tar.gz",
                archiveType: "tgz",
            }],
        },
        {
            kind: "DScript",
            modules: [
                f`Managed/module.config.dsc`,
                f`Rules.CSharp/module.config.dsc`,
                f`Tests/module.config.dsc`,
                f`${Environment.getPathValue("BUILDXL_BIN")}/Sdk/Sdk.Transformers/package.config.dsc`,
            ],
        },
    ],
    mounts: [
        {
            name: a`Out`,
            path: p`Out/Bin`,
            trackSourceFileChanges: true,
            isWritable: true,
            isReadable: true,
            isScrubbable: true,
        },
    ],
});
