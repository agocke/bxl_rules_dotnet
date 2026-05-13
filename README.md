# bxl_rules_csharp — C# Build Rules for BuildXL

A C# compilation SDK built on [bxl_rules](https://github.com/agocke/bxl_rules). It provides `csharp_library` and `csharp_binary`, but the consuming workspace is responsible for supplying the .NET toolchain — typically by downloading an SDK archive with BuildXL's `Download` resolver.

## Quick Start

### 1. Add resolvers to `config.dsc`

```typescript
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
            root: d`/path/to/bxl_rules_csharp`,
        },
    ],
});
```

The example above uses the Linux x64 SDK archive. Swap the URL and `compilerPath` for the host RID you want to support.

Third-party workspaces that use both `bxl_rules` and `bxl_rules_csharp` should declare both: `bxl_rules` via `GitRepository` (or another resolver of their choice) and this repo as a normal DScript root/module.

### 2. Construct a toolchain from the downloaded SDK

```typescript
import * as CSharp from "Sdk.Rules.CSharp";

const dotnetSdk = importFrom("DotNetSdk").extracted;

const toolchain = CSharp.csharpToolchainFromContents({
    name: "dotnet-sdk",
    contents: dotnetSdk,
    hostPath: "dotnet",
    compilerPath: "sdk/10.0.201/Roslyn/bincore/csc.dll",
});
```

You can also build a toolchain from explicit `File`s with `CSharp.csharpToolchain({ compiler, hostExe })` if your workspace acquires the host/compiler some other way.

### 3. Write a BUILD.dsc

```typescript
import * as CSharp from "Sdk.Rules.CSharp";

const dotnetSdk = importFrom("DotNetSdk").extracted;
const toolchain = CSharp.csharpToolchainFromContents({
    contents: dotnetSdk,
    compilerPath: "sdk/10.0.201/Roslyn/bincore/csc.dll",
});

const systemRuntime = dotnetSdk.getFile(
    r`packs/Microsoft.NETCore.App.Ref/10.0.5/ref/net10.0/System.Runtime.dll`
);

@@public
export const myLib = CSharp.csharp_library({
    name: "MyLib",
    toolchain: toolchain,
    srcs: ["Foo.cs", "Bar.cs"],
    fileRefs: [systemRuntime],
});

@@public
export const myApp = CSharp.csharp_binary({
    name: "MyApp",
    toolchain: toolchain,
    srcs: ["Program.cs"],
    fileRefs: [systemRuntime],
    deps: [myLib],
});
```

Source files are labels (strings), not file paths. The rule resolves them, invokes the supplied Roslyn compiler, and returns a `CSharpInfo` provider with the compiled assembly.

## Rules

### csharp_library

Compiles a C# class library (DLL).

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `string` | required | Assembly name (becomes `{name}.dll`) |
| `toolchain` | `CSharpToolchain` | required | Toolchain that provides `dotnet` and `csc.dll` |
| `srcs` | `Label[]` | required | C# source file labels |
| `refs` | `Label[]` | `[]` | Assembly reference labels (resolved to files) |
| `fileRefs` | `File[]` | `[]` | Pre-resolved assembly references (e.g. from downloads or NuGet) |
| `deps` | `CSharpInfo[]` | `[]` | Dependencies on other C# targets |
| `optimize` | `boolean` | `false` | Enable compiler optimizations |
| `allowUnsafe` | `boolean` | `false` | Allow unsafe code blocks |
| `nullable` | `string` | `"disable"` | Nullable context: `disable`, `enable`, `warnings`, `annotations` |
| `defines` | `string[]` | `[]` | Preprocessor define constants |
| `nowarn` | `string[]` | `[]` | Warning codes to suppress |
| `analyzers` | `File[]` | `[]` | Roslyn analyzer/source-generator DLLs |
| `compilerOptions` | `string[]` | `[]` | Additional raw csc flags |

### csharp_binary

Same attributes as `csharp_library`. Compiles with `/target:exe` so the assembly has an entry point. The output is still a `.dll` because .NET runs it through the host.

## Providers

Both rules return `CSharpInfo`:

```typescript
interface CSharpInfo extends Provider {
    kind: "CSharpInfo";
    binary: File;             // the compiled assembly
    refs: File[];             // direct references
    deps: CSharpInfo[];       // dependencies
    defaultInfo: DefaultInfo; // files + runfiles
}
```

Use `deps` to chain targets — direct dependency outputs are passed as references automatically:

```typescript
const lib = CSharp.csharp_library({ name: "Lib", toolchain, srcs: ["Lib.cs"], ... });
const app = CSharp.csharp_binary({ name: "App", toolchain, srcs: ["Main.cs"], deps: [lib], ... });
```

## Labels vs File References

Rules accept two kinds of references:

- **`refs: Label[]`** — string labels resolved by the framework. Use for workspace-local files.
- **`fileRefs: File[]`** — pre-resolved `File` objects. Use for files from downloaded SDKs, NuGet packages, or other resolvers.

Both are merged before compilation.

## Analyzers and Source Generators

Pass Roslyn analyzer/source-generator DLLs via `analyzers`:

```typescript
CSharp.csharp_binary({
    name: "MyTest",
    toolchain: toolchain,
    srcs: ["Test.cs"],
    analyzers: [mySourceGeneratorDll],
    fileRefs: [systemRuntime],
});
```

## Toolchain Helpers

### csharpToolchain

Construct a toolchain from explicit files:

```typescript
const toolchain = CSharp.csharpToolchain({
    hostExe: someDotnetFile,
    compiler: someCscFile,
});
```

### csharpToolchainFromContents

Construct a toolchain from an extracted SDK/archive:

```typescript
const toolchain = CSharp.csharpToolchainFromContents({
    contents: importFrom("DotNetSdk").extracted,
    hostPath: "dotnet",
    compilerPath: "sdk/10.0.201/Roslyn/bincore/csc.dll",
});
```

This keeps the repo shippable: the SDK is downloaded by the consuming workspace instead of being checked into `bxl_rules_csharp`.

## Compiler Flags

The SDK always passes these csc flags:

- `/noconfig`
- `/nostdlib+`
- `/deterministic+`
- `/utf8output`
- `/nologo`

## Related

- **[bxl_rules](https://github.com/agocke/bxl_rules)** — The base rules framework this SDK is built on
- **[rules_dotnet](https://github.com/nicholasgasior/rules_dotnet)** — The Bazel C# rules that inspired this SDK
