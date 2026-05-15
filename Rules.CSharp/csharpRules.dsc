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
 *   const toolchain = CSharp.csharpToolchain({
 *       hostExe: f`/path/to/dotnet`,
 *       compiler: f`/path/to/csc.dll`,
 *   });
 *
 *   const myLib = CSharp.csharp_library({
 *       name: "MyLib",
 *       toolchain: toolchain,
 *       srcs: globR(d`.`, "*.cs"),
 *       refs: ["@SomePackage//path:Dependency.dll"],
 *   });
 */

import * as Rules from "Sdk.Rules";
import {Cmd} from "Sdk.Transformers";

// ============================================================================
//  CSharpToolchain — declares what tools C# rules need
// ============================================================================

/**
 * The C# toolchain — analogous to Bazel's `//dotnet:toolchain_type`.
 */

@@public
export interface CSharpToolchain extends Rules.Toolchain {
    /** The Roslyn csc.dll to invoke. */
    compiler: File;

    /** The dotnet host executable (runs csc.dll). */
    hostExe: File;

    /**
     * Extra arguments passed to the dotnet host BEFORE the compiler DLL.
     * Useful for `--additionalprobingpath` when SDK symlinks are missing.
     */
    hostArguments?: Argument[];
}

/**
 * Create a CSharpToolchain from files.
 */
@@public
export function csharpToolchain(args: { name?: string, compiler: File, hostExe: File, hostArguments?: Argument[] }): CSharpToolchain {
    return {
        kind: "CSharpToolchain",
        name: args.name || "csharp_toolchain",
        compiler: args.compiler,
        hostExe: args.hostExe,
        hostArguments: args.hostArguments
    };
}

/**
 * Create a CSharpToolchain from the contents of an extracted SDK/archive.
 *
 * This is the common path when a workspace acquires the .NET SDK with
 * BuildXL's Download resolver and wants to pass the resulting content to
 * these rules.
 */
@@public
export function csharpToolchainFromContents(args: {
    name?: string,
    contents: StaticDirectory,
    compilerPath: string,
    hostPath?: string,
    hostArguments?: Argument[],
}): CSharpToolchain {
    return csharpToolchain({
        name: args.name || "csharp_toolchain",
        compiler: findFileInContents(args.contents, args.compilerPath),
        hostExe: findFileInContents(args.contents, args.hostPath || "dotnet"),
        hostArguments: args.hostArguments,
    });
}

function findFileInContents(contents: StaticDirectory, path: string): File {
    return contents.assertExistence(r`${path}`);
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
    binary: File;

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

    /**
     * Analyzer config files (passed via /analyzerconfig:).
     * Used to provide build_property.* / build_metadata.* options to
     * source generators and analyzers. Typically `.globalconfig` files.
     */
    analyzerConfigs?: File[];

    /**
     * External packages available for `@pkg//path:file` label resolution
     * in `srcs` and `refs`. Forwarded to the underlying Rules.rule
     * definition; see Sdk.Rules for the resolution semantics.
     */
    externalPackages?: Map<string, StaticDirectory>;

    /** Toolchain to use for this target. */
    toolchain: CSharpToolchain;
}

// ============================================================================
//  Resolved attributes (what impl receives — labels → files)
// ============================================================================

interface CSharpResolvedAttrs {
    name: string;
    srcs: Rules.Artifact[];
    refs: Rules.Artifact[];
    deps: CSharpInfo[];
    optimize: boolean;
    allowUnsafe: boolean;
    nullable: string;
    defines: string[];
    nowarn: string[];
    compilerOptions: string[];
    analyzers: Rules.Artifact[];
    analyzerConfigs: Rules.Artifact[];
}

/**
 * Resolve label-based attrs to file-based attrs.
 * Analogous to Bazel's attr.label_list() declarations — this tells
 * the framework which fields are labels and how to resolve them.
 */
function resolveCSharpAttrs(attrs: CSharpCommonAttrs, resolver: Rules.LabelResolver): CSharpResolvedAttrs {
    return {
        name: attrs.name,
        srcs: resolver.resolveAll(attrs.srcs),
        refs: attrs.refs ? resolver.resolveAll(attrs.refs) : [],
        deps: attrs.deps || [],
        optimize: attrs.optimize || false,
        allowUnsafe: attrs.allowUnsafe || false,
        nullable: attrs.nullable || "disable",
        defines: attrs.defines || [],
        nowarn: attrs.nowarn || [],
        compilerOptions: attrs.compilerOptions || [],
        analyzers: (attrs.analyzers || []).map(f => Rules.sourceArtifact(f)),
        analyzerConfigs: (attrs.analyzerConfigs || []).map(f => Rules.sourceArtifact(f))
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
function createCSharpRule<TAttrs extends CSharpCommonAttrs>(doc: string, targetType: TargetType): (args: TAttrs) => CSharpInfo {
    return (args: TAttrs) => Rules.rule<TAttrs, CSharpResolvedAttrs, CSharpToolchain, CSharpInfo>({
        doc: doc,
        toolchain: args.toolchain,
        externalPackages: args.externalPackages,
        resolve: resolveCSharpAttrs,
        impl: (ctx) => compileImpl(ctx.actions, ctx.args, ctx.toolchain, targetType)
    })(args);
}

@@public
export const csharp_library = createCSharpRule<CsharpLibraryAttrs>(
    "Compile a C# class library",
    "library"
);

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
export const csharp_binary = createCSharpRule<CsharpBinaryAttrs>(
    "Compile a C# exe",
    "exe"
);

// ============================================================================
//  compile implementation (shared)
// ============================================================================

type TargetType = "library" | "exe";

function compileImpl(actions: Rules.Actions, args: CSharpResolvedAttrs, toolchain: CSharpToolchain, targetType: TargetType): CSharpInfo {
    // .NET Core assemblies are always .dll — /target:exe just sets the entry point.
    const outDll = actions.declareOutput(args.name + ".dll");

    // All refs are pre-resolved: label refs + file refs + transitive deps
    const depRefs = args.deps.map(dep => Rules.sourceArtifact(dep.binary));
    const allRefs = [...args.refs, ...depRefs];

    // Build csc command line from the supplied toolchain.
    // Host arguments (e.g., --additionalprobingpath) go before csc.dll.
    const cscArgs: Argument[] = [
        ...(toolchain.hostArguments || []),
        Cmd.argument(Rules.cmdInput(Rules.sourceArtifact(toolchain.compiler))),
        Cmd.option("/out:", Rules.cmdOutput(outDll)),
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
        ...args.analyzers.map(a => Cmd.option("/analyzer:", Rules.cmdInput(a))),
        ...args.analyzerConfigs.map(c => Cmd.option("/analyzerconfig:", Rules.cmdInput(c))),
        ...allRefs.map(r => Cmd.option("/reference:", Rules.cmdInput(r))),
        ...args.srcs.map(s => Cmd.argument(Rules.cmdInput(s)))
    ];

    const outputs = actions.run({
        tool: toolchain.hostExe,
        arguments: cscArgs,
        outputs: [outDll],
        description: `csc [${targetType}]: ${args.name}`
    });

    const binary = Rules.getFile(outputs[0]);
    const refFiles = allRefs.map(r => Rules.getFile(r));

    // Collect transitive runfiles: this target's binary + all ref assemblies.
    const depRunfiles = args.deps.reduce(
        (acc: File[], dep: CSharpInfo) => [...acc, ...(dep.defaultInfo.runfiles || [])],
        [] as File[]
    );
    const runfiles = [binary, ...refFiles, ...depRunfiles];

    return {
        kind: "CSharpInfo",
        binary: binary,
        refs: refFiles,
        deps: args.deps,
        defaultInfo: Rules.defaultInfo({ files: [binary], runfiles: runfiles })
    };
}
