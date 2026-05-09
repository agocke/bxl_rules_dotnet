// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

/**
 * Sdk.Rules.CSharp — Bazel-style C# build rules for BuildXL.
 *
 * Uses the rule()/toolchain pattern from Sdk.Rules so that:
 * - Rule implementations never hardcode tool paths
 * - The workspace provides a concrete CSharpToolchain
 * - Callers just pass attrs (like a Bazel BUILD file)
 *
 * Usage:
 *   import * as CSharp from "Sdk.Rules.CSharp";
 *
 *   const myLib = CSharp.csharp_library({
 *       name: "MyLib",
 *       srcs: globR(d`.`, "*.cs"),
 *       refs: [f`path/to/Dependency.dll`],
 *   });
 */

import * as Rules from "Sdk.Rules";
import {Artifact, Cmd, Transformer} from "Sdk.Transformers";

// ============================================================================
//  CSharpToolchain — declares what tools C# rules need
// ============================================================================

/**
 * The C# toolchain — analogous to Bazel's `//dotnet:toolchain_type`.
 *
 * Tools are bundled with this SDK package. The toolchain references them
 * via paths relative to the SDK module directory — no external labels or
 * absolute paths needed.
 */

// SDK package root — navigate from this spec's directory to the package root.
// When this SDK is distributed as a downloaded archive, the layout is:
//   bxl_rules_csharp/
//     Rules.CSharp/csharpRules.dsc  ← this file
//     sdk/dotnet, sdk/roslyn/csc.dll
//     xunit/xunit.console.dll
const sdkPackageRoot = d`${Context.getSpecFileDirectory().parent}`;
const sdkToolsDir = d`${sdkPackageRoot}/sdk`;

@@public
export interface CSharpToolchain extends Rules.Toolchain {
    /** The Roslyn csc.dll to invoke. */
    compiler: File;

    /** The dotnet host executable (runs csc.dll). */
    hostExe: File;
}

/**
 * Create a CSharpToolchain from files.
 */
@@public
export function csharpToolchain(args: { name?: string, compiler: File, hostExe: File }): CSharpToolchain {
    return {
        kind: "CSharpToolchain",
        name: args.name || "csharp_toolchain",
        compiler: args.compiler,
        hostExe: args.hostExe
    };
}

// Default toolchain — uses tools bundled with this SDK package.
const defaultToolchain = csharpToolchain({
    name: "default_csharp_toolchain",
    compiler: f`${sdkToolsDir}/roslyn/csc.dll`,
    hostExe: f`${sdkToolsDir}/dotnet`
});

/**
 * Get the default C# toolchain. Useful for repo-specific rules
 * that need the dotnet host (e.g., test runners).
 */
@@public
export function getDefaultToolchain(): CSharpToolchain {
    return defaultToolchain;
}

// ============================================================================
//  CSharpInfo provider
// ============================================================================

/**
 * Provider returned by all C# rules, carrying the compiled assembly
 * and its transitive reference closure.
 */
@@public
export interface CSharpInfo extends Rules.Provider {
    /** The compiled assembly (DLL or EXE). */
    binary: DerivedFile;

    /** Direct assembly references used to compile this target. */
    refs: File[];

    /** Dependencies (other CSharpInfo providers). */
    deps: CSharpInfo[];

    /** Default output info. */
    defaultInfo: Rules.DefaultInfo;
}

// ============================================================================
//  Caller-facing attributes (labels)
// ============================================================================

@@public
export interface CSharpCommonAttrs {
    /** Target name. Becomes the output assembly name. */
    name: string;

    /** C# source files (labels, resolved by the rule). */
    srcs: Rules.Label[];

    /** Assembly reference labels (resolved by the rule). */
    refs?: Rules.Label[];

    /** Pre-resolved assembly references (e.g., from NuGet importFrom). */
    fileRefs?: File[];

    /** Dependencies on other C# targets built by this SDK. */
    deps?: CSharpInfo[];

    /** Enable optimizations. Default: false. */
    optimize?: boolean;

    /** Allow unsafe blocks. Default: false. */
    allowUnsafe?: boolean;

    /** Nullable context. Default: undefined (compiler default). */
    nullable?: string;

    /** Additional #define constants. */
    defines?: string[];

    /** Warning codes to suppress. */
    nowarn?: string[];

    /** Additional raw compiler options. */
    compilerOptions?: string[];

    /** Roslyn analyzer/source-generator DLLs (passed via /analyzer:). */
    analyzers?: File[];

    /** Override the default toolchain. */
    toolchain?: CSharpToolchain;
}

// ============================================================================
//  Resolved attributes (what impl receives — labels → files)
// ============================================================================

interface CSharpResolvedAttrs {
    name: string;
    srcs: File[];
    refs: File[];
    deps: CSharpInfo[];
    optimize: boolean;
    allowUnsafe: boolean;
    nullable: string;
    defines: string[];
    nowarn: string[];
    compilerOptions: string[];
    analyzers: File[];
}

/**
 * Resolve label-based attrs to file-based attrs.
 * Analogous to Bazel's attr.label_list() declarations — this tells
 * the framework which fields are labels and how to resolve them.
 */
function resolveCSharpAttrs(attrs: CSharpCommonAttrs, resolver: Rules.LabelResolver): CSharpResolvedAttrs {
    const refFiles = attrs.refs ? resolver.resolveAll(attrs.refs) : [];
    return {
        name: attrs.name,
        srcs: resolver.resolveAll(attrs.srcs),
        refs: [...refFiles, ...(attrs.fileRefs || [])],
        deps: attrs.deps || [],
        optimize: attrs.optimize || false,
        allowUnsafe: attrs.allowUnsafe || false,
        nullable: attrs.nullable || "disable",
        defines: attrs.defines || [],
        nowarn: attrs.nowarn || [],
        compilerOptions: attrs.compilerOptions || [],
        analyzers: attrs.analyzers || []
    };
}

// ============================================================================
//  csharp_library — rule declaration
// ============================================================================

@@public
export interface CsharpLibraryAttrs extends CSharpCommonAttrs {
}

/**
 * Build a C# class library (DLL).
 *
 * Analogous to rules_dotnet's `csharp_library`.
 */
@@public
export const csharp_library = Rules.rule<CsharpLibraryAttrs, CSharpResolvedAttrs, CSharpToolchain, CSharpInfo>({
    doc: "Compile a C# class library",
    toolchain: defaultToolchain,
    resolve: resolveCSharpAttrs,
    impl: (ctx) => compileImpl(ctx.actions, ctx.args, ctx.toolchain, "library")
});

// ============================================================================
//  csharp_binary — rule declaration
// ============================================================================

@@public
export interface CsharpBinaryAttrs extends CSharpCommonAttrs {
}

/**
 * Build a C# executable (EXE).
 *
 * Analogous to rules_dotnet's `csharp_binary`.
 */
@@public
export const csharp_binary = Rules.rule<CsharpBinaryAttrs, CSharpResolvedAttrs, CSharpToolchain, CSharpInfo>({
    doc: "Compile a C# exe",
    toolchain: defaultToolchain,
    resolve: resolveCSharpAttrs,
    impl: (ctx) => compileImpl(ctx.actions, ctx.args, ctx.toolchain, "exe")
});

// ============================================================================
//  compile implementation (shared)
// ============================================================================

type TargetType = "library" | "exe";

function compileImpl(actions: Rules.Actions, args: CSharpResolvedAttrs, toolchain: CSharpToolchain, targetType: TargetType): CSharpInfo {
    // .NET Core assemblies are always .dll — /target:exe just sets the entry point.
    const outDll = actions.declareFile(args.name + ".dll");

    // All refs are pre-resolved: label refs + file refs + transitive deps
    const depRefs = args.deps.map(dep => dep.binary);
    const allRefs = [...args.refs, ...depRefs];

    // Build csc command line — toolchain files are bundled, no resolution needed
    const cscArgs: Argument[] = [
        Cmd.argument(Artifact.input(toolchain.compiler)),
        Cmd.option("/out:", Artifact.output(outDll.path)),
        Cmd.argument(`/target:${targetType}`),
        Cmd.argument("/noconfig"),
        Cmd.argument("/nostdlib+"),
        Cmd.argument("/deterministic+"),
        Cmd.argument("/utf8output"),
        Cmd.argument("/nologo"),
        ...(args.nowarn.length > 0
            ? [Cmd.argument(`/nowarn:${args.nowarn.join(",")}`)]
            : []),
        ...(args.optimize ? [Cmd.argument("/optimize+")] : []),
        ...(args.allowUnsafe ? [Cmd.argument("/unsafe+")] : []),
        Cmd.argument(`/nullable:${args.nullable}`),
        ...args.defines.map(d => Cmd.argument(`/define:${d}`)),
        ...args.compilerOptions.map(o => Cmd.argument(o)),
        ...args.analyzers.map(a => Cmd.option("/analyzer:", Artifact.input(a))),
        ...allRefs.map(r => Cmd.option("/reference:", Artifact.input(r))),
        ...args.srcs.map(s => Cmd.argument(Artifact.input(s)))
    ];

    const outputs = actions.run({
        tool: toolchain.hostExe,
        arguments: cscArgs,
        outputs: [outDll],
        description: `csc [${targetType}]: ${args.name}`
    });

    const binary = outputs[0];

    // Collect transitive runfiles: this target's binary + all ref assemblies.
    const depRunfiles = args.deps.reduce(
        (acc: File[], dep: CSharpInfo) => [...acc, ...(dep.defaultInfo.runfiles || [])],
        [] as File[]
    );
    const runfiles = [binary, ...allRefs, ...depRunfiles];

    return {
        kind: "CSharpInfo",
        binary: binary,
        refs: allRefs,
        deps: args.deps,
        defaultInfo: Rules.defaultInfo({ files: [binary], runfiles: runfiles })
    };
}
