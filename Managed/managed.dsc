// Minimal Sdk.Managed stub — satisfies auto-generated NuGet package specs.
// Only the types/functions referenced by the NuGet resolver's generated code
// are provided here. This is NOT BuildXL's full Sdk.Managed.

@@public
export interface ManagedNugetPackage {}

namespace Factory {
    export declare const qualifier: {};

    @@public
    export function createNugetPackage(
        name: string,
        version: string,
        contents: StaticDirectory,
        compile: any[],
        runtime: any[],
        dependencies: any[]
    ): ManagedNugetPackage {
        return <ManagedNugetPackage>{};
    }

    @@public
    export function createBinaryFromFiles(
        binary: File,
        pdb?: File,
        documentation?: File
    ): any {
        return binary;
    }
}
