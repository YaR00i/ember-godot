import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const WATCHDOG_OWNER_ENV = "EMBER_GODOT_MCP_OWNER_PID";
const WATCH_INTERVAL_MS = 500;
const GRACEFUL_SHUTDOWN_MS = 1500;

function isProcessAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    return false;
  }

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function startWatchdog(ownerPid) {
  const timer = setInterval(() => {
    if (!isProcessAlive(ownerPid)) {
      process.exit(0);
    }
  }, WATCH_INTERVAL_MS);

  timer.unref();
}

function killProcessTree(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    return;
  }

  if (process.platform === "win32") {
    spawnSync("taskkill.exe", ["/PID", String(pid), "/T", "/F"], {
      stdio: "ignore",
      windowsHide: true,
    });
    return;
  }

  try {
    process.kill(pid, "SIGKILL");
  } catch {
    // The child has already stopped.
  }
}

function runSupervisor() {
  const supervisorPath = fileURLToPath(import.meta.url);
  const projectRoot = path.resolve(path.dirname(supervisorPath), "..");
  const comspec = process.env.ComSpec || "cmd.exe";
  const watchdogImport = `--import=${pathToFileURL(supervisorPath).href}`;
  const nodeOptions = [process.env.NODE_OPTIONS, watchdogImport]
    .filter(Boolean)
    .join(" ");

  const child = spawn(
    comspec,
    ["/d", "/s", "/c", "npx -y @keeveeg/godot-mcp"],
    {
      cwd: projectRoot,
      env: {
        ...process.env,
        NODE_OPTIONS: nodeOptions,
        [WATCHDOG_OWNER_ENV]: String(process.pid),
      },
      stdio: ["pipe", "pipe", "inherit"],
      windowsHide: true,
    },
  );

  let stopping = false;
  let forceTimer = null;
  const parentPid = process.ppid;

  process.stdin.pipe(child.stdin);
  child.stdout.pipe(process.stdout);

  const stop = () => {
    if (stopping) {
      return;
    }

    stopping = true;
    clearInterval(parentTimer);

    if (child.exitCode !== null || child.signalCode !== null) {
      return;
    }

    child.stdin.end();
    forceTimer = setTimeout(() => killProcessTree(child.pid), GRACEFUL_SHUTDOWN_MS);
    forceTimer.unref();
  };

  const parentTimer = setInterval(() => {
    if (!isProcessAlive(parentPid)) {
      stop();
    }
  }, WATCH_INTERVAL_MS);
  parentTimer.unref();

  process.stdin.once("end", stop);
  process.stdin.once("close", stop);
  process.stdin.once("error", stop);
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);

  child.once("error", (error) => {
    console.error(`[godot-mcp-supervisor] Failed to start: ${error.message}`);
    process.exitCode = 1;
    stop();
  });

  child.once("exit", (code, signal) => {
    clearInterval(parentTimer);
    if (forceTimer) {
      clearTimeout(forceTimer);
    }

    process.stdin.unpipe(child.stdin);
    process.stdin.pause();
    process.exit(code ?? (signal ? 1 : 0));
  });

  process.once("exit", () => {
    if (child.exitCode === null && child.signalCode === null) {
      killProcessTree(child.pid);
    }
  });
}

const watchdogOwnerPid = Number.parseInt(process.env[WATCHDOG_OWNER_ENV] || "", 10);

if (Number.isSafeInteger(watchdogOwnerPid) && watchdogOwnerPid > 0) {
  startWatchdog(watchdogOwnerPid);
} else {
  runSupervisor();
}
