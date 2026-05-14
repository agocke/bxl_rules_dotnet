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
 *   const toolchain = CSharp.csharpToolchainFromDotNetSdk({
 *       contents: importFrom("DotNetSdk").extracted,
 *       sdkVersion: "10.0.201",
 *   });
 *
 *   const myLib = CSharp.csharp_library({
 *       name: "MyLib",
 *       toolchain: toolchain,
 *       srcs: globR(d`.`, "*.cs"),
 *       fileRefs: [f`path/to/Dependency.dll`],
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
    /** Tagged-interface brand. Do not set or read. */
    __csharpToolchainBrand: any;

    /** The Roslyn csc.dll to invoke. */
    compiler: File;

    /** The dotnet host executable (runs csc.dll). */
    hostExe: File;

    /** Additional compiler payload files that must be present beside csc.dll (for example Roslyn/bincore/**). */
    compilerPayload: File[];
}

function createCSharpToolchain(args: {
    name?: string,
    compiler: File,
    hostExe: File,
    compilerPayload: File[],
}): CSharpToolchain {
    return {
        __csharpToolchainBrand: undefined,
        kind: "CSharpToolchain",
        name: args.name || "csharp_toolchain",
        compiler: args.compiler,
        hostExe: args.hostExe,
        compilerPayload: args.compilerPayload,
    };
}

function createCSharpToolchainFromContents(args: {
    name?: string,
    contents: StaticDirectory,
    compilerPath: string,
    compilerPayloadPath: string,
}): CSharpToolchain {
    return createCSharpToolchain({
        name: args.name || "csharp_toolchain",
        compiler: findFileInContents(args.contents, args.compilerPath),
        hostExe: findFileInContents(args.contents, "dotnet"),
        compilerPayload: findFilesInContents(
            args.contents,
            args.compilerPayloadPath
        ),
    });
}

function findFileInContents(contents: StaticDirectory, path: string): File {
    return contents.assertExistence(r`${path}`);
}

function findFilesInContents(contents: StaticDirectory, path: string): File[] {
    const directoryRoot = d`${contents.root}/${r`${path}`}`;
    const literalFiles = globR(directoryRoot, "*");
    Contract.assert(literalFiles.length > 0,
        `expected directory "${path}" to exist in extracted contents`);
    const directoryRootString = directoryRoot.toDiagnosticString();
    return literalFiles.map(file => {
        const filePath = file.path.toDiagnosticString();
        const prefix = `${directoryRootString}/`;
        Contract.assert(filePath.startsWith(prefix),
            `expected "${filePath}" to be within "${directoryRootString}"`);
        const relativePath = filePath.slice(prefix.length);
        return contents.assertExistence(r`${path}/${relativePath}`);
    });
}

/**
 * Create a CSharpToolchain from an extracted .NET SDK.
 *
 * Resolves the `dotnet` host, `sdk/<ver>/Roslyn/bincore/csc.dll`, and the
 * full `sdk/<ver>/Roslyn/bincore` directory payload required by Roslyn.
 */
@@public
export function csharpToolchainFromDotNetSdk(args: {
    name?: string,
    contents: StaticDirectory,
    sdkVersion: string,
}): CSharpToolchain {
    const roslynBincorePath = `sdk/${args.sdkVersion}/Roslyn/bincore`;
    return createCSharpToolchainFromContents({
        name: args.name || "csharp_toolchain",
        contents: args.contents,
        compilerPath: `${roslynBincorePath}/csc.dll`,
        compilerPayloadPath: roslynBincorePath,
    });
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
        refs: [...refFiles, ...(attrs.fileRefs || []).map(f => Rules.sourceArtifact(f))],
        deps: attrs.deps || [],
        optimize: attrs.optimize || false,
        allowUnsafe: attrs.allowUnsafe || false,
        nullable: attrs.nullable || "disable",
        defines: attrs.defines || [],
        nowarn: attrs.nowarn || [],
        compilerOptions: attrs.compilerOptions || [],
        analyzers: (attrs.analyzers || []).map(f => Rules.sourceArtifact(f))
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
    const cscArgs: Argument[] = [
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
        ...allRefs.map(r => Cmd.option("/reference:", Rules.cmdInput(r))),
        ...args.srcs.map(s => Cmd.argument(Rules.cmdInput(s)))
    ];

    const outputs = actions.run({
        tool: toolchain.hostExe,
        arguments: cscArgs,
        outputs: [outDll],
        dependencies: toolchain.compilerPayload.map(f => Rules.sourceArtifact(f)),
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
