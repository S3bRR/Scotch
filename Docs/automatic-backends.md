# Application graphics backends

The main Backend picker selects a renderer directly. New bottles and bottles
previously set to Auto use D3DMetal (DX11/12). Explicit selections are retained.
Applications inherit the bottle renderer unless their program profile opts into
Auto or chooses a different backend. Open the program’s context
menu → Program Settings → Graphics to inspect architecture, APIs, recommendation,
reason and missing runtime components. Auto inspects the executable without
running it; Choose Backend stores an explicit per-application manual override
that takes priority over the bottle policy.

The bounded PE inspector reads normal and delay imports, plus adjacent DLL
dependencies to depth three. It caps file counts and bytes, rejects invalid
RVAs and does not follow dependency symlinks outside the program directory.
It does not scan an entire Steam library or execute untrusted code to detect
an API. Imports cannot identify every dynamically loaded API or prove speed.

Auto selects D3DMetal for an unambiguous supported 64-bit DirectX 12 executable
and Zink for an unambiguous OpenGL executable. DirectX 10/11 receives a
recommendation while retaining the current bottle setup, because several
backends support it. Launchers, mixed/unknown APIs, incomplete inspection and
application-supplied graphics wrappers retain the bottle setting. Custom
graphics environment variables also prevent automatic inference. There is no
automatic benchmarking, crash retry loop or community profile feed in this
version.

Manual choices take priority. Otherwise Auto first reuses a user-confirmed
working setup when its executable/dependency content, runtime identity,
arguments, environment and relevant bottle settings still match. Old
confirmations remain saved when they become stale. A successful process launch
only records what was launched; it never marks rendering as working. After
checking the application, press Remember Most Recent Launch as Working in its
settings. Forget Working Choice takes effect when Save is pressed.

The resolved graphics configuration is still bottle-wide. A different
application's launch may change the bottle's selected backend. Such a change
requires idle Wine processes, validates the installed backend without copying
the bottle and transfers maintenance directly into a launch
lease. Another launch, manual backend change or update cannot replace that
configuration during the protected transition. Saves and settings stay in the
prefix. Launches needing the same configuration may share the engine.

The matched Wine engine is used for all backends, including when a legacy
bottle first adopts it. Steam's helper has a separate,
path-scoped engine policy; games retain their selected renderer.

EXE programs start directly through Wine.app with their executable directory as
the working directory; shell-associated files retain the shell launch path.

New shortcuts and Run In Terminal use `ScotchCmd run-configured-path`, reading
the saved profile at launch time. Previously generated shortcuts contain their
old commands; recreate them to gain this behavior. Raw CLI launches also use
the saved graphics selection. Existing and future unreadable profiles are not
silently replaced with defaults.

`bash scripts/test_program_graphics.sh` tests parser fixtures, delayed and local
dependencies, malformed files, content changes, manual/working priorities,
missing backends, idle guards, maintenance-to-launch transfer, backup-free backend changes and
future profile preservation. Runtime availability is simulated only for the
isolated metadata transition tests; live rendering checks use real verified
runtime files.
