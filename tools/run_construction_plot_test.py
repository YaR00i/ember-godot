"""Refresh and run the native construction gate in an existing disposable editor copy."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe"
SOURCES = (
    "addons/ember_import/ember_plot_construction.gd",
    "addons/ember_import/ember_terrain_plan_dialog.gd",
    "addons/ember_import/ember_voxel_bush_generator.gd",
    "addons/ember_import/ember_voxel_generator.gd",
    "addons/ember_import/ember_world_editor.gd",
    "scripts/ember_fruit_tree.gd",
    "scripts/ember_tree_surface.gd",
    "scripts/ember_tree_surface_geometry.gd",
    "shaders/ember_hedge_leaves.gdshader",
    "shaders/ember_hedge_leaf_atlas.gdshader",
    "tools/editor_test_construction_plot.gd",
)
PLUGIN = "res://addons/ember_plot_test/plugin.cfg"
RESULT_PREFIX = "CONSTRUCTION_PLOT "


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--copy", type=Path, required=True, help="Prepared ember-entry-* project in the system temp directory")
    parser.add_argument("--evidence", type=Path, required=True, help="Output folder for screenshots and the editor log")
    args = parser.parse_args()
    project = args.copy.resolve()
    if (project == ROOT or project.parent != Path(tempfile.gettempdir()).resolve()
            or not project.name.startswith("ember-entry-")):
        parser.error("--copy must name a disposable ember-entry-* project in the system temp directory")
    config = (project / "project.godot").resolve()
    if not config.is_relative_to(project) or not config.is_file():
        parser.error("--copy must contain its own project.godot")
    text = config.read_text(encoding="utf-8")
    if PLUGIN not in text:
        parser.error("--copy must already have the construction fixture plugin enabled")
    destinations = [(project / relative).resolve() for relative in SOURCES]
    if any(not target.is_relative_to(project) for target in destinations):
        parser.error("a staged source points outside the disposable project")
    for relative, target in zip(SOURCES, destinations):
        shutil.copyfile(ROOT / relative, target)

    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    # The fixture drives Godot directly and does not need the shared MCP listener.
    original = text
    text = text.replace(', "res://addons/godot_mcp/plugin.cfg"', '')
    if 'config/use_custom_user_dir=true' not in text:
        text = text.replace('[application]\n', '[application]\nconfig/use_custom_user_dir=true\n'
                            f'config/custom_user_dir="Ember construction QA/{project.name}"\n', 1)
    if text != original:
        config.write_text(text, encoding="utf-8")
    log = evidence / "editor.log"
    env = dict(os.environ, EMBER_PLOT_EVIDENCE=evidence.as_posix())
    result = subprocess.run(
        [str(ENGINE), "--path", str(project), "--editor", "--rendering-method", "forward_plus",
         "--resolution", "1600x900", "--log-file", str(log)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace", timeout=240,
    )
    summaries = [json.loads(line[len(RESULT_PREFIX):]) for line in result.stdout.splitlines()
                 if line.startswith(RESULT_PREFIX)]
    if result.returncode or len(summaries) != 1 or not summaries[0].get("pass"):
        print(result.stdout)
        raise SystemExit(f"Construction test did not pass. See {log}")
    print(f"PASS construction plot. Screenshots and log: {evidence}")


if __name__ == "__main__":
    main()
