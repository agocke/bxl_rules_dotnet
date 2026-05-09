# bxl_rules_csharp — C# Build Rules for BuildXL

A C# compilation SDK built on [bxl_rules](../bxl_rules/). Provides `csharp_library` and `csharp_binary` rules with a bundled .NET SDK — no system-installed compiler needed.

## Quick Start

### 1. Add to your `config.dsc`

```typescript
config({
    resolvers: [
        { kind: "DScript", root: d`/path/to/bxl_rules` },
        { kind: "DScript", root: d`/path/to/bxl_rules_csharp` },
        // ... your modules
    ]
});
```

### 2. Write a BUILD.dsc

```typescript
import * as CSharp from "Sdk.Rules.CSharp";

@@public
export const myLib = CSharp.csharp_library({
    name: "MyLib",
    srcs: ["Foo.cs", "Bar.cs"],
    refs: ["//path/to/ref:System.Runtime.dll"]
});

@@public
export const myApp = CSharp.csharp_binary({
    name: "MyApp",
    srcs: ["Program.cs"],
    deps: [myLib]
});
```

That's it. Source files are labels (strings), not file paths. The rule resolves them, invokes the bundled Roslyn compiler, and returns a `CSharpInfo` provider with the compiled assembly.

## Rules

### csharp_library

Compiles a C# class library (DLL).

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `string` | required | Assembly name (becomes `{name}.dll`) |
| `srcs` | `Label[]` | required | C# source file labels |
| `refs` | `Label[]` | `[]` | Assembly reference labels (resolved to files) |
| `fileRefs` | `File[]` | `[]` | Pre-resolved assembly references (e.g., from NuGet) |
| `deps` | `CSharpInfo[]` | `[]` | Dependencies on other C# targets |
| `optimize` | `boolean` | `false` | Enable compiler optimizations |
| `allowUnsafe` | `boolean` | `false` | Allow unsafe code blocks |
| `nullable` | `string` | `"disable"` | Nullable context: `disable`, `enable`, `warnings`, `annotations` |
| `defines` | `string[]` | `[]` | Preprocessor define constants |
| `nowarn` | `string[]` | `[]` | Warning codes to suppress |
| `analyzers` | `File[]` | `[]` | Roslyn analyzer/source-generator DLLs |
| `compilerOptions` | `string[]` | `[]` | Additional raw csc flags |

### csharp_binary

Same attributes as `csharp_library`. Compiles with `/target:exe` so the assembly has an entry point. The output is still a `.dll` (this is .NET Core — the host runs it via `dotnet exec`).

## Providers

Both rules return `CSharpInfo`:

```typescript
interface CSharpInfo extends Provider {
    kind: "CSharpInfo";
    binary: DerivedFile;       // the compiled assembly
    refs: File[];              // direct references
    deps: CSharpInfo[];        // dependencies
    defaultInfo: DefaultInfo;  // files + runfiles
}
```

Use `deps` to chain targets — transitive references are collected automatically:

```typescript
const lib = CSharp.csharp_library({ name: "Lib", srcs: ["Lib.cs"], ... });
const app = CSharp.csharp_binary({ name: "App", srcs: ["Main.cs"], deps: [lib] });
// App automatically gets Lib.dll as a reference
```

## Labels vs File References

Rules accept two kinds of references:

- **`refs: Label[]`** — string labels resolved by the framework. Use for workspace-local files:
  ```typescript
  refs: ["//artifacts/bin/System.Runtime/ref/Release/net11.0:System.Runtime.dll"]
  ```

- **`fileRefs: File[]`** — pre-resolved `File` objects. Use for files from NuGet packages or other resolvers:
  ```typescript
  fileRefs: [importFrom("xunit.core").Contents.all.getFile(r`lib/netstandard1.1/xunit.core.dll`)]
  ```

Both are merged before compilation. The split exists because NuGet packages produce `File` objects that aren't workspace-relative paths.

## Analyzers and Source Generators

Pass Roslyn analyzer/source-generator DLLs via `analyzers`:

```typescript
CSharp.csharp_binary({
    name: "MyTest",
    srcs: ["Test.cs"],
    analyzers: [mySourceGeneratorDll]  // passed as /analyzer: to csc
});
```

The analyzer runs during compilation and can inject generated source (e.g., a test runner `Main()` method).

## Toolchain

The C# SDK bundles its own .NET SDK and Roslyn compiler — no system install needed. Tools are located relative to the SDK package:

```
bxl_rules_csharp/
├── sdk/
│   ├── dotnet              — .NET host executable
│   ├── host/               — .NET host libraries
│   ├── shared/             — .NET shared framework
│   └── roslyn/             — Roslyn compiler (csc.dll + dependencies)
├── Rules.CSharp/
│   ├── module.config.dsc
│   └── csharpRules.dsc     — csharp_library, csharp_binary
└── Managed/
    ├── module.config.dsc
    └── managed.dsc          — Sdk.Managed stub (for NuGet resolver)
```

To access the toolchain from a macro (e.g., a test runner that needs the dotnet host):

```typescript
import * as CSharp from "Sdk.Rules.CSharp";

const toolchain = CSharp.getDefaultToolchain();
// toolchain.hostExe — the dotnet executable
// toolchain.compiler — csc.dll
```

## Writing a Test Macro

A common pattern is writing a repo-specific test macro that wraps `csharp_binary` with baked-in dependencies. Here's the pattern:

```typescript
import * as CSharp from "Sdk.Rules.CSharp";
import * as Defs from "Defs";

export function my_test(args: { name: string, srcs: Label[] }) {
    // Labels pass through — the rule resolves them
    const testBinary = CSharp.csharp_binary({
        name: args.name,
        srcs: args.srcs,
        refs: Defs.COMMON_REFS,          // label-based refs
        fileRefs: Defs.NUGET_REFS,       // NuGet file refs
        analyzers: [Defs.TEST_GENERATOR]  // source generator
    });

    // Run the test...
    return testBinary;
}
```

The macro never calls label resolution — it passes labels straight through to the rule.

## Compiler Flags

The SDK always passes these csc flags (matching Bazel's rules_dotnet):

- `/noconfig` — don't use default response file
- `/nostdlib+` — don't auto-reference mscorlib
- `/deterministic+` — reproducible builds
- `/utf8output` — UTF-8 console output
- `/nologo` — suppress banner

## Related

- **[bxl_rules](../bxl_rules/)** — The base rules framework this SDK is built on
- **[rules_dotnet](https://github.com/nicholasgasior/rules_dotnet)** — The Bazel C# rules that inspired this SDK
