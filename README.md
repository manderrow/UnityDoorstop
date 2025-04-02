<p align="center">
  <img height="256" width="256" src="assets/img/icon.png">
</p>

<h1 align="center">Unity Doorstop</h1>

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/manderrow/UnityDoorstop/build.yml?branch=master)](https://github.com/manderrow/UnityDoorstop/actions/workflows/build.yml)
[![nightly.link artifacts](https://img.shields.io/badge/Artifacts-nightly.link-blueviolet)](https://nightly.link/manderrow/UnityDoorstop/workflows/build/master)

---

Doorstop is a tool to execute managed .NET assemblies inside Unity as early as possible.

## Features

- **Runs first**: Doorstop runs its code before Unity can do so
- **Configurable**: An elementary configuration file allows you to specify your assembly to execute
- **Multiplatform**: Supports Windows, Linux, macOS
- **Debugger support**: Allows to debug managed assemblies in Visual Studio, Rider or dnSpy _without modifications to Mono_

## Unity runtime support

Doorstop supports executing .NET assemblies in both Unity Mono and Il2Cpp runtimes.
Depending on the runtime the game uses, Doorstop tries to run your assembly as follows:

- On Unity Mono, your assembly is executed in the same runtime. As a result
    - You don't need to include your custom Common Language Runtime (CLR); the one bundled with the game is used
    - Your assembly is run alongside other Unity code
    - You can access all Unity API directly
- On Il2Cpp, your assembly is executed in CoreCLR runtime because Il2Cpp cannot run managed assemblies. As a result:
    - You need to include .NET 6 or newer CoreCLR runtime with your managed assembly
    - Your assembly is run in a runtime that is isolated from Il2Cpp
    - You can access Il2Cpp runtime by interacting with its native `il2cpp_` API

## Building

Doorstop uses [Zig](https://ziglang.org/) to build the project. To build, run `zig build`.

## Minimal injection example

To have Doorstop inject your code, create `Entrypoint` class into `Doorstop` namespace.
Define a public static `Start` method in it:

```cs
using System.IO;

namespace Doorstop;

class Entrypoint
{
  public static void Start()
  {
      File.WriteAllText("doorstop_hello.log", "Hello from Unity!");
  }
}
```

You can then define any code you want in `Start`.

**NOTE:** On UnityMono, Doorstop bootstraps your assembly with a minimal number of assemblies and minimal configuration.
This early execution allows for some interesting tricks, like redirecting the loading of some game assemblies.
Bear also in mind that some of the Unity runtime is not initialized at such an early stage, limiting the code you can execute.
You might need to appropriately pause the execution of your code until the moment you want to modify the game.

### Doorstop environment variables

Doorstop sets some environment variables useful for code execution:

| Environment variable          | Description                                                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `DOORSTOP_INITIALIZED`        | Always set to `TRUE`. Use to determine if your code is run via Doorstop.                                                          |
| `DOORSTOP_INVOKE_DLL_PATH`    | Path to the assembly executed by Doorstop ~~relative to the current working directory~~ (this part is not even true upstream).    |
| `DOORSTOP_PROCESS_PATH`       | Path to the application executable where the injected assembly is run.                                                            |
| `DOORSTOP_MANAGED_FOLDER_DIR` | _UnityMono_: Path to the game's `Managed` folder. _Il2Cpp_: Path to CoreCLR's base class library folder.                          |
| `DOORSTOP_DLL_SEARCH_DIRS`    | Paths where the runtime searchs assemblies from by default, separated by OS-specific separator (`;` on windows and `:` on \*nix). |
| `DOORSTOP_MONO_LIB_PATH`      | _Only on UnityMono_: Full path to the mono runtime library.                                                                       |

### Debugging

Doorstop 4 supports debugging the assemblies in the runtime.

#### Debugging in UnityMono

To enable debugging, set `debug_enabled` to `true` and optionally change the debug server address via `debug_address` (see [configuration options](#doorstop-configuration)).
After launching the game, you may connect to the debugger using the server address (default is `127.0.0.1:10000`).
By default, the game won't wait for the debugger to connect; you may change the behaviour with the `debug_suspend` option.

> **If you use dnSpy**, you can use the `Debug > Start Debugging > Debug engine > Unity` option, automatically setting the correct debugging configuration.
> Doorstop detects dnSpy and automatically enables debugging without any extra configuration.

#### Debugging in Il2Cpp

Debugging is automatically enabled in CoreCLR.

To start debugging, compile your DLL in debug mode (with embedded or portable symbols) and start the game with the debugger of your choice.
Alternatively, attach a debugger to the game once it is running. All standard CoreCLR debuggers should detect the CoreCLR runtime in the game.

Moreover, hot reloading is supported for Visual Studio, Rider and other debuggers with .NET 6 hot reloading feature enabled.

**Note that you can only debug managed code!** Because the game code is unmanaged (i.e. Il2Cpp), you cannot directly debug the actual game code.
Consider using native debuggers like GDB and visual debugging tools like IDA or Ghidra to debug actual game code.

## Doorstop configuration

Doorstop is reasonably configurable via environment variables.

The following environment variables are consumed by Doorstop:

Platform specific variables will be indicated as such.

- `bool` = `1` or `0`
- `string` = any valid environment variable value.
- `path` = an absolute path

| Name                                     | Type     | Description                                                                                          |
| ---------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------- |
| `DOORSTOP_ENABLED`                       | `bool`   | Enable or disable Doorstop.                                                                          |
| `DOORSTOP_REDIRECT_OUTPUT_LOG`           | `bool`   | _Only on Windows_: If `true` Unity's output log is redirected to `<current folder>\output_log.txt`   |
| `DOORSTOP_TARGET_ASSEMBLY`               | `path`   | Path to the assembly to load and execute.                                                            |
| `DOORSTOP_BOOT_CONFIG_OVERRIDE`          | `path`   | Overrides the boot.config file path.                                                                 |
| `DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE` | `string` | Overrides default Mono DLL search path                                                               |
| `DOORSTOP_MONO_DEBUG_ENABLED`            | `bool`   | If true, Mono debugger server will be enabled                                                        |
| `DOORSTOP_MONO_DEBUG_SUSPEND`            | `bool`   | Whether to suspend the game execution until the debugger is attached.                                |
| `DOORSTOP_MONO_DEBUG_ADDRESS`            | `string` | The address to use for the Mono debugger server.                                                     |
| `DOORSTOP_CLR_CORLIB_DIR`                | `path`   | Path to coreclr library that contains the CoreCLR runtime                                            |
| `DOORSTOP_CLR_RUNTIME_CORECLR_PATH`      | `path`   | Path to the directory containing the managed core libraries for CoreCLR (`mscorlib`, `System`, etc.) |

## License

Doorstop 4 is licensed under LGPLv2.1. You can view the entire license [here](LICENSE).
