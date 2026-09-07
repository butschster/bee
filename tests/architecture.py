"""Check the small production graph without walking legacy or local state."""
from pathlib import Path
import re
import yaml

ROOT = Path(__file__).resolve().parents[1]
assert not (ROOT / "legacy").exists(), "Keep the legacy archive outside the repository"
lock = yaml.safe_load((ROOT / "wippy.lock").read_text())
assert lock["directories"]["src"] == "./src", "Production must load only src/"
assert not lock.get("modules"), "Core boot must not depend on fixture/test packages"
config = yaml.safe_load((ROOT / ".wippy.yaml").read_text())
assert not config.get("workspace", {}).get("replacements"), "Review dependency replacements before admitting them"
entries = {}
for path in (ROOT / "src").rglob("_index.yaml"):
    document = yaml.safe_load(path.read_text())
    for entry in document["entries"]:
        identity = f'{document["namespace"]}:{entry["name"]}'
        assert identity not in entries, f"Duplicate registry identity {identity}"
        entries[identity] = entry
        for name, target in entry.get("imports", {}).items():
            assert not target.startswith(("poc.", "casha.")), (identity, name, target)
            if identity.startswith(("bee.desktop:", "bee.session:", "bee.terminal:", "bee.settings:", "bee.processes:")):
                allowed_imports = ("bee.desktop:", "bee.protocol:")
                if identity.startswith("bee.terminal:"):
                    allowed_imports += ("bee.terminal:",)
                if identity.startswith("bee.processes:"):
                    allowed_imports += ("bee.processes:",)
                if identity.startswith("bee.settings:"):
                    allowed_imports += ("bee.settings:",)
                assert target.startswith(allowed_imports), (identity, target)
        source = entry.get("source", "")
        if source.startswith("file://"):
            source_path = (path.parent / source.removeprefix("file://")).resolve()
            assert source_path.is_relative_to(ROOT / "src"), (identity, source_path)
            text = source_path.read_text()
            assert not re.search(r"(?:::|:)\s*any\b", text), identity
            assert "/home/" not in text and "legacy/" not in text, identity
            if identity == "bee.desktop:model":
                assert "require(" not in text and "tty." not in text, identity
        if identity not in {"bee.settings:app", "bee.processes:app"}:
            assert entry.get("meta", {}).get("type") not in {"bee.application", "test"}, ("Non-core entry in src", identity)

app_policy = entries["bee:app_policy"]["policy"]
assert app_policy == {"actions": "*", "resources": "*", "effect": "deny"}, app_policy
for entry in entries.values():
    for target in entry.get("imports", {}).values():
        assert target in entries, target
assert entries["bee:application_admission"]["definitions"] == ["bee.settings:app", "bee.processes:app"]
assert {i for i, e in entries.items() if e["kind"] == "process.lua"} == {"bee.applications:broker", "bee.session:main", "bee.terminal:main", "bee.workspace:main", "bee.settings:app", "bee.processes:app"}
assert {i for i, e in entries.items() if e.get("meta", {}).get("type") == "bee.application"} == {"bee.settings:app", "bee.processes:app"}
assert not entries["bee.settings:app"].get("lifecycle", {}).get("auto_start", False)
assert set(entries["bee:settings_policy"]["policy"]["actions"]) == {
    "tty.observe", "tty.input", "tty.resize", "process.send"}
assert set(entries["bee:presenter_policy"]["policy"]["actions"]) == {
    "tty.observe", "tty.input", "tty.resize", "process.send", "process.monitor"}
assert entries["bee:processes_policy"]["policy"] == {
    "actions": ["system.read"], "resources": ["hosts", "memory", "goroutines", "supervisor"], "effect": "allow"}
assert not entries["bee.processes:app"].get("lifecycle", {}).get("auto_start", False)
assert "security" not in entries["bee.terminal:main"]["modules"]
assert "command" not in entries["bee.terminal:main"].get("meta", {})
assert entries["bee.terminal:render"]["modules"] == ["tty"]
for pure in ["bee.desktop:layout", "bee.terminal:bindings"]:
    assert not entries[pure].get("modules"), pure
assert {i for i, e in entries.items() if e["kind"] == "terminal.host"} == {"bee:terminal"}
assert not any(e["kind"] in {"http.service", "db.sql.sqlite", "exec.native"} for e in entries.values())
print(f"Architecture: {len(entries)} entries; two on-demand applications, closed imports, denied ambient app authority")

# Inspect what Wippy actually loads, including transitive dependency entries.
import json
import os
import shutil
import subprocess
import tempfile

runtime = Path(os.environ.get("BEE_RUNTIME", ROOT / ".wippy/bin/wippy")).resolve()
allowed = {"bee", "bee.applications", "bee.desktop", "bee.protocol",
           "bee.session", "bee.settings", "bee.processes", "bee.terminal", "bee.workspace"}

def check_loaded(cwd, packed=False):
    loaded = json.loads(subprocess.check_output([str(runtime), "registry", "list", "--json"], cwd=cwd))
    assert {e["id"] for e in loaded} == set(entries), "Loaded entries differ from the declared core"
    for entry in loaded:
        namespace = entry["id"].split(":", 1)[0]
        assert namespace in allowed, f'Unexpected loaded namespace: {entry["id"]}'
        if entry["id"] not in {"bee.settings:app", "bee.processes:app"}:
            assert entry.get("meta", {}).get("type") not in {"test", "bee.application"}, entry["id"]
    print(f"{'Pack' if packed else 'Source'} registry: {len(loaded)} entries; no legacy namespaces")

check_loaded(ROOT)
with tempfile.TemporaryDirectory(prefix="bee-pack-audit-") as directory:
    folder = Path(directory)
    shutil.copy2(ROOT / "dist/bee.wapp", folder / "bee.wapp")
    (folder / "wippy.lock").write_text("directories:\n  modules: ./vendor\n  src: ./bee.wapp\nmodules: []\n")
    check_loaded(folder, packed=True)
