// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

/**
 * Workspace config for validating bxl_rules_dotnet against a local bxl_rules checkout.
 *
 * Set BXL_RULES_ROOT to the root of a local agocke/bxl_rules checkout before
 * invoking `./run-tests.sh`.
 */

config({
    resolvers: [
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
                f`${Environment.getPathValue("BXL_RULES_ROOT")}/Rules/module.config.dsc`,
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
