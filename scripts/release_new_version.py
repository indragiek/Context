#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "rich>=13.7.0",
#     "click>=8.1.7",
#     "lxml>=5.1.0",
#     "markdown2>=2.4.12",
#     "pyyaml>=6.0.1",
# ]
# ///
"""
Context Release Automation Script

Environment Variables:
    APPLE_TEAM_ID: Apple App Store Connect Team ID (required)
    APPLE_KEYCHAIN_PROFILE: Name of the Keychain item created by running:
        `$(xcode-select -p)/usr/bin/notarytool store-credentials`
        Defaults to "App Store Connect Profile"
"""

import argparse
import re
import subprocess
import sys
import os
import shutil
import time
import yaml  # type: ignore[import]
from datetime import datetime, timezone
from pathlib import Path
from typing import Tuple, Optional, Dict, List, Any, Union
import xml.etree.ElementTree as ET
from rich.console import Console  # type: ignore[import]
from rich.progress import (  # type: ignore[import]
    Progress,
    SpinnerColumn,
    TextColumn,
    BarColumn,
    TaskProgressColumn,
    TimeRemainingColumn,
)
from rich.panel import Panel  # type: ignore[import]
from rich.table import Table  # type: ignore[import]
from rich.tree import Tree  # type: ignore[import]
from rich.rule import Rule  # type: ignore[import]
from rich.syntax import Syntax  # type: ignore[import]
from rich.prompt import Confirm  # type: ignore[import]
from rich import print as rprint  # type: ignore[import]
from lxml import etree  # type: ignore[import]
import markdown2  # type: ignore[import]

console = Console()

# Global config object
CONFIG: Optional['Config'] = None

# Global verbosity settings
VERBOSE: bool = False
QUIET: bool = False
DEBUG: bool = False


# Status icons
class Icons:
    SUCCESS = "[green]✓[/green]"
    WARNING = "[yellow]⚠[/yellow]"
    ERROR = "[red]✗[/red]"
    INFO = "[blue]ℹ[/blue]"
    PROGRESS = "[cyan]➤[/cyan]"


class ReleaseError(Exception):
    """Custom exception for release script errors"""

    pass


class Config:
    """Configuration container for release settings"""

    def __init__(self, config_dict: Dict[str, Any]):
        self._config = config_dict

    def __getitem__(self, key: str) -> Any:
        """Get a configuration value"""
        return self._config[key]

    def get(self, key: str, default: Any = None) -> Any:
        """Get a configuration value with a default"""
        return self._config.get(key, default)


def load_config(config_path: Optional[Path] = None) -> Config:
    """Load configuration from YAML file"""
    # If no explicit path provided, look for release.yaml in current directory
    if config_path is None:
        config_path = Path("release.yaml")

    if not config_path.exists():
        error_msg = f"""
[bold red]Configuration file not found: {config_path}[/bold red]

The release automation script requires a configuration file to run.

Please create a 'release.yaml' file in your project root with the following format:

[yellow]# Example release.yaml configuration[/yellow]
[dim]app_name: "YourApp"
bundle_identifier: "com.yourcompany.YourApp"
xcode_project: "YourApp/YourApp.xcodeproj"
scheme: "YourApp"
website_url: "https://www.yourapp.com/"
github_owner: "yourusername"
github_repo: "YourApp"
minimum_system_version: "15.0"  # Optional, defaults to "15.0"[/dim]

You can also specify a custom configuration file path using:
  [cyan]./release_new_version.py --config /path/to/config.yaml ...[/cyan]
"""
        console.print(error_msg)
        raise ReleaseError("Configuration file not found")

    try:
        with open(config_path, "r") as f:
            config_dict = yaml.safe_load(f)

        if not config_dict:
            raise ReleaseError("Configuration file is empty")

        return Config(config_dict)

    except yaml.YAMLError as e:
        raise ReleaseError(f"Failed to parse configuration file: {e}")
    except Exception as e:
        raise ReleaseError(f"Failed to load configuration file: {e}")


class RollbackManager:
    """Manages rollback of changes if script fails"""

    def __init__(self):
        self.backup_files = {}
        self.created_files = []
        self.temp_dirs = []

    def backup_file(self, filepath: Path):
        """Backup a file before modifying it"""
        if filepath.exists():
            self.backup_files[filepath] = filepath.read_text()

    def track_created_file(self, filepath: Path):
        """Track a newly created file for deletion on rollback"""
        self.created_files.append(filepath)

    def track_temp_dir(self, dirpath: Path):
        """Track a temporary directory for cleanup"""
        self.temp_dirs.append(dirpath)

    def rollback(self):
        """Rollback all tracked changes"""
        console.print("\n[yellow]Rolling back changes...[/yellow]")

        # Restore backed up files
        for filepath, content in self.backup_files.items():
            try:
                filepath.write_text(content)
                console.print(f"  [dim]Restored {filepath}[/dim]")
            except Exception as e:
                console.print(f"  [red]Failed to restore {filepath}: {e}[/red]")

        # Delete created files
        for filepath in self.created_files:
            try:
                if filepath.exists():
                    filepath.unlink()
                    console.print(f"  [dim]Deleted {filepath}[/dim]")
            except Exception as e:
                console.print(f"  [red]Failed to delete {filepath}: {e}[/red]")

        # Clean up temp directories
        for dirpath in self.temp_dirs:
            try:
                if dirpath.exists():
                    shutil.rmtree(dirpath)
                    console.print(f"  [dim]Cleaned up {dirpath}[/dim]")
            except Exception as e:
                console.print(f"  [red]Failed to clean up {dirpath}: {e}[/red]")

        console.print("[yellow]Rollback complete[/yellow]\n")


def run_command(
    cmd: List[str],
    check: bool = True,
    capture_output: bool = True,
    show_output: Optional[bool] = None,
    **kwargs: Any,
) -> subprocess.CompletedProcess[str]:
    """Run a command with error handling"""
    # Determine if we should show output based on verbosity settings
    if show_output is None:
        show_output = VERBOSE

    if show_output and not QUIET:
        console.print(f"[dim]Running: {' '.join(cmd)}[/dim]")

    try:
        return subprocess.run(
            cmd, check=check, capture_output=capture_output, text=True, **kwargs
        )
    except subprocess.CalledProcessError as e:
        if capture_output:
            if not QUIET:
                console.print(f"{Icons.ERROR} Command failed: {' '.join(cmd)}")
            if e.stdout and (VERBOSE or DEBUG):
                console.print(f"[yellow]stdout:[/yellow] {e.stdout}")
            if e.stderr:
                console.print(f"[red]stderr:[/red] {e.stderr}")
        raise ReleaseError(f"Command failed: {' '.join(cmd)}") from e


def get_notarytool_path() -> str:
    """Get the path to notarytool from Xcode developer directory"""
    try:
        result = run_command(["xcode-select", "-p"], capture_output=True)
        developer_dir = result.stdout.strip()
        return os.path.join(developer_dir, "usr", "bin", "notarytool")
    except Exception:
        return "notarytool"  # Fallback to PATH


def unlock_keychain() -> bool:
    """Interactively unlock the keychain"""
    console.print("\n[yellow]Keychain Access Required[/yellow]")
    console.print("The script needs to access your keychain for:")
    console.print("  • Code signing with Developer ID certificate")
    console.print("  • Notarization credentials")
    console.print("  • Sparkle EdDSA signing key")
    console.print()
    console.print("Please enter your keychain password when prompted...")

    try:
        # Use interactive mode to unlock the keychain
        # This prompts the user directly and doesn't expose the password
        result = subprocess.run(["security", "-i", "unlock-keychain"], check=False)

        if result.returncode != 0:
            console.print("[red]Failed to unlock keychain[/red]")
            return False

        console.print("[green]✓[/green] Keychain unlocked successfully")
        return True

    except Exception as e:
        console.print(f"[red]Error unlocking keychain: {e}[/red]")
        return False


def validate_tools() -> None:
    """Validate that all required tools are installed"""
    tools = {
        "xcodebuild": "Xcode command line tools",
        "gh": "GitHub CLI",
        "hdiutil": "macOS disk image utility",
        "codesign": "macOS code signing tool",
        "xcbeautify": "Xcode build output formatter",
    }

    missing_tools = []

    # Check each tool without progress display (to avoid nested Progress contexts)
    for tool, description in tools.items():
        if shutil.which(tool) is None:
            missing_tools.append(f"{tool} ({description})")

    # Check for notarytool in Xcode developer directory
    notarytool_path = get_notarytool_path()
    if not os.path.exists(notarytool_path):
        missing_tools.append(
            f"notarytool (Apple notarization tool at {notarytool_path})"
        )

    # Check for sign_update script
    sign_update_path = Path("scripts/bin/sparkle/sign_update")
    if not sign_update_path.exists():
        missing_tools.append(
            f"sign_update (Sparkle signing tool at {sign_update_path})"
        )

    if missing_tools:
        console.print("[red]Missing required tools:[/red]")
        for tool in missing_tools:
            console.print(f"  • {tool}")
        raise ReleaseError("Please install missing tools before proceeding")

    # Success message will be printed by run_parallel_tasks


def show_pre_release_checklist(warnings: List[str]) -> bool:
    """Show an interactive pre-release checklist"""
    if QUIET:
        return True

    console.print()
    console.rule("[bold blue]Pre-Release Checklist[/bold blue]")

    # Create a table for the checklist
    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Status", style="dim")
    table.add_column("Item")

    # Check git status
    git_clean = not any("uncommitted changes" in w for w in warnings)
    table.add_row(
        Icons.SUCCESS if git_clean else Icons.WARNING,
        "Working directory clean"
        if git_clean
        else "Working directory has uncommitted changes",
    )

    # Check branch
    on_main = not any("Not on main branch" in w for w in warnings)
    table.add_row(
        Icons.SUCCESS if on_main else Icons.WARNING,
        "On main branch" if on_main else "Not on main branch",
    )

    # Check if up to date
    up_to_date = not any("behind origin/main" in w for w in warnings)
    table.add_row(
        Icons.SUCCESS if up_to_date else Icons.WARNING,
        "Up to date with remote" if up_to_date else "Local branch is behind remote",
    )

    # Check changelog
    changelog_ready = not any("Unreleased" in w for w in warnings)
    table.add_row(
        Icons.SUCCESS if changelog_ready else Icons.WARNING,
        "Changelog has unreleased content"
        if changelog_ready
        else "Changelog needs update",
    )

    # Check disk space
    disk_ok = not any("Low disk space" in w for w in warnings)
    table.add_row(
        Icons.SUCCESS if disk_ok else Icons.WARNING,
        "Sufficient disk space" if disk_ok else "Low disk space",
    )

    console.print(table)
    console.print()

    if warnings:
        return Confirm.ask(
            "[yellow]There are warnings. Continue anyway?[/yellow]", default=False
        )
    else:
        return Confirm.ask("[green]Ready to proceed?[/green]", default=True)


def preflight_checks() -> List[str]:
    """Run pre-flight checks and return warnings"""
    warnings = []

    # Check git status
    result = run_command(["git", "status", "--porcelain"], check=False)
    if result.stdout.strip():
        uncommitted_files = result.stdout.strip().split("\n")
        warnings.append(
            f"Working directory has {len(uncommitted_files)} uncommitted changes"
        )

    # Check if on main branch
    result = run_command(["git", "branch", "--show-current"])
    current_branch = result.stdout.strip()
    if current_branch != "main":
        warnings.append(f"Not on main branch (currently on '{current_branch}')")

    # Check if up to date with remote
    run_command(["git", "fetch"], check=False)
    result = run_command(
        ["git", "rev-list", "HEAD..origin/main", "--count"], check=False
    )
    if result.stdout.strip() != "0":
        warnings.append("Local branch is behind origin/main")

    # Check if changelog has unreleased content
    changelog_path = Path("CHANGELOG.md")
    if changelog_path.exists():
        content = changelog_path.read_text()
        if "## Unreleased" not in content:
            warnings.append("No '## Unreleased' section in CHANGELOG.md")
        else:
            # Check if unreleased section has content
            import re

            unreleased_match = re.search(
                r"## Unreleased\n(.*?)(?=\n## |$)", content, re.DOTALL
            )
            if unreleased_match and not unreleased_match.group(1).strip():
                warnings.append("'## Unreleased' section in CHANGELOG.md is empty")
    else:
        warnings.append("CHANGELOG.md not found")

    # Check if appcast.xml exists
    if not Path("appcast.xml").exists():
        warnings.append("appcast.xml not found")

    # Check disk space
    import shutil

    stat = shutil.disk_usage(".")
    free_gb = stat.free / (1024**3)
    if free_gb < 5:
        warnings.append(
            f"Low disk space: {free_gb:.1f} GB free (recommend at least 5 GB)"
        )

    return warnings


def run_parallel_tasks(
    tasks: List[Tuple[str, Any, tuple]], description: str = "Running tasks"
) -> List[Any]:
    """Run multiple tasks sequentially (parallelization removed) and return their results"""
    results = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task(description, total=len(tasks))

        for task_name, func, args in tasks:
            try:
                # Run task sequentially
                result = func(*args)
                results.append(result)
                console.print(f"[green]✓[/green] {task_name}")
            except Exception as e:
                console.print(f"[red]✗[/red] {task_name}: {e}")
                raise
            finally:
                progress.advance(task)

    return results


def validate_environment() -> Dict[str, str]:
    """Validate all required environment variables"""
    required_vars = {"APPLE_TEAM_ID": "Apple Team ID for code signing"}

    optional_vars = {
        "APPLE_KEYCHAIN_PROFILE": (
            "Keychain profile for notarization",
            "App Store Connect Profile",
        ),
        "SENTRY_AUTH_TOKEN": ("Sentry authentication token", None),
    }

    missing = []
    env_vars = {}

    # Check required variables
    for var, description in required_vars.items():
        value = os.environ.get(var)
        if not value:
            missing.append(f"{var}: {description}")
        else:
            env_vars[var] = value

    # Check optional variables and set defaults
    for var, (description, default) in optional_vars.items():
        value = os.environ.get(var, default)
        if value:
            env_vars[var] = value

    if missing:
        console.print("[red]Missing required environment variables:[/red]")
        for var in missing:
            console.print(f"  • {var}")
        raise ReleaseError("Please set required environment variables")

    return env_vars


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Automate building and publishing app releases",
        epilog="""
Environment Variables:
    APPLE_TEAM_ID: Apple App Store Connect Team ID (required)
    APPLE_KEYCHAIN_PROFILE: Keychain profile name (overrides config file)
        """,
    )
    parser.add_argument(
        "version_type",
        choices=["major", "minor", "patch", "skip"],
        help="Type of version increment (or 'skip' to keep current version)",
    )
    parser.add_argument(
        "archive_path",
        type=Path,
        help="Path to directory where archives will be generated",
    )
    parser.add_argument(
        "--config", type=Path, help="Path to configuration file (default: release.yaml)"
    )
    parser.add_argument(
        "--sentry-org", help="Sentry organization slug for uploading dSYMs"
    )
    parser.add_argument(
        "--sentry-project", help="Sentry project slug for uploading dSYMs"
    )
    parser.add_argument(
        "--skip-sparkle",
        action="store_true",
        help="Skip Sparkle update signing and appcast update (useful if EdDSA key is not accessible)",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show detailed command output"
    )
    parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Only show critical errors and final result",
    )
    parser.add_argument(
        "--debug", action="store_true", help="Show full stack traces on errors"
    )

    args = parser.parse_args()

    # Validate archive path
    if not args.archive_path.exists():
        args.archive_path.mkdir(parents=True, exist_ok=True)

    return args


def get_current_versions(project_path: Path, bundle_identifier: str) -> Tuple[int, str]:
    """Extract current version numbers from Xcode project for the specified bundle identifier"""
    with open(project_path, "r") as f:
        content = f.read()

    # Find all buildSettings sections
    build_settings_pattern = r"buildSettings\s*=\s*\{([^}]+)\};"

    current_version = None
    marketing_version = None

    for match in re.finditer(build_settings_pattern, content, re.DOTALL):
        settings_block = match.group(1)

        # Check if this block contains our bundle identifier
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_identifier};" in settings_block:
            # Extract CURRENT_PROJECT_VERSION from this block
            current_match = re.search(
                r"CURRENT_PROJECT_VERSION = (\d+);", settings_block
            )
            if current_match:
                current_version = int(current_match.group(1))

            # Extract MARKETING_VERSION from this block
            marketing_match = re.search(
                r"MARKETING_VERSION = ([\d.]+);", settings_block
            )
            if marketing_match:
                marketing_version = marketing_match.group(1)

            # We found a valid buildSettings block, we can use these values
            if current_version is not None and marketing_version is not None:
                break

    if current_version is None or marketing_version is None:
        raise ReleaseError(
            f"Could not find version numbers for bundle identifier {bundle_identifier}"
        )

    return current_version, marketing_version


def show_version_table(
    current_marketing: str,
    current_project: int,
    new_marketing: str,
    new_project: int,
    version_type: str,
) -> None:
    """Display version information in a nice table"""
    if QUIET:
        return

    table = Table(
        title="Version Information", show_header=True, header_style="bold cyan"
    )
    table.add_column("Type", style="dim")
    table.add_column("Current", justify="center")
    table.add_column("→", justify="center", style="dim")
    table.add_column(
        "New",
        justify="center",
        style="bold green" if version_type != "skip" else "yellow",
    )

    table.add_row("Marketing Version", current_marketing, "→", new_marketing)
    table.add_row("Build Number", str(current_project), "→", str(new_project))

    if version_type != "skip":
        table.add_row("Increment Type", "", "", version_type.capitalize())
    else:
        table.add_row("Action", "", "", "[yellow]Skip (using existing)[/yellow]")

    console.print()
    console.print(table)
    console.print()


def validate_version(version: str) -> bool:
    """Validate semantic version format (X.Y.Z)"""
    pattern = r"^\d+\.\d+\.\d+$"
    return bool(re.match(pattern, version))


def increment_versions(
    current_project: int, marketing: str, version_type: str
) -> Tuple[int, str]:
    """Calculate new version numbers based on increment type"""
    # Handle skip case - return current versions unchanged
    if version_type == "skip":
        return current_project, marketing

    # Validate current version format
    if not validate_version(marketing):
        raise ReleaseError(
            f"Invalid marketing version format: {marketing}. Expected X.Y.Z format."
        )

    parts = marketing.split(".")
    if len(parts) != 3:
        raise ReleaseError(f"Invalid marketing version format: {marketing}")

    major, minor, patch = map(int, parts)

    if version_type == "major":
        new_project = current_project + 100
        new_marketing = f"{major + 1}.0.0"
    elif version_type == "minor":
        new_project = current_project + 10
        new_marketing = f"{major}.{minor + 1}.0"
    else:  # patch
        new_project = current_project + 1
        new_marketing = f"{major}.{minor}.{patch + 1}"

    return new_project, new_marketing


def update_project_versions(
    project_path: Path,
    bundle_identifier: str,
    new_project: int,
    new_marketing: str,
    rollback_manager: RollbackManager,
) -> None:
    """Update version numbers in Xcode project file for the specified bundle identifier"""
    # Backup the file before modifying
    rollback_manager.backup_file(project_path)

    with open(project_path, "r") as f:
        content = f.read()

    # We need to update version numbers only in buildSettings blocks that contain our bundle identifier
    # Use a more complex approach to handle nested braces correctly

    def find_matching_brace(text: str, start_pos: int) -> int:
        """Find the closing brace for an opening brace at start_pos"""
        count = 1
        pos = start_pos + 1
        while pos < len(text) and count > 0:
            if text[pos] == "{":
                count += 1
            elif text[pos] == "}":
                count -= 1
            pos += 1
        return pos - 1 if count == 0 else -1

    modified_content = content
    offset = 0

    # Find all buildSettings blocks
    for match in re.finditer(r"buildSettings\s*=\s*\{", content):
        start = match.end() - 1  # Position of the opening brace
        end = find_matching_brace(content, start)

        if end == -1:
            continue

        settings_block = content[start + 1 : end]

        # Check if this block contains our bundle identifier
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_identifier};" in settings_block:
            # Update CURRENT_PROJECT_VERSION in this block
            updated_block = re.sub(
                r"CURRENT_PROJECT_VERSION = \d+;",
                f"CURRENT_PROJECT_VERSION = {new_project};",
                settings_block,
            )

            # Update MARKETING_VERSION in this block
            updated_block = re.sub(
                r"MARKETING_VERSION = [\d.]+;",
                f"MARKETING_VERSION = {new_marketing};",
                updated_block,
            )

            # Replace the block in the content
            modified_content = (
                modified_content[: start + 1 + offset]
                + updated_block
                + modified_content[end + offset :]
            )

            # Update offset for subsequent replacements
            offset += len(updated_block) - len(settings_block)

    with open(project_path, "w") as f:
        f.write(modified_content)


def show_release_notes_preview(changelog_items: str, version: str) -> None:
    """Show a preview of the release notes"""
    if QUIET:
        return

    console.print()
    console.rule(f"[bold blue]Release Notes Preview - v{version}[/bold blue]")

    # Create a panel with syntax highlighting for markdown
    preview_panel = Panel(
        Syntax(changelog_items, "markdown", theme="monokai", line_numbers=False),
        title="[bold]Changelog Items[/bold]",
        border_style="blue",
        padding=(1, 2),
    )

    console.print(preview_panel)
    console.print()


def process_changelog(
    new_project: int, new_marketing: str, rollback_manager: RollbackManager
) -> str:
    """Process CHANGELOG.md and generate release notes HTML"""
    changelog_path = Path("CHANGELOG.md")

    # Backup CHANGELOG.md before modifying
    rollback_manager.backup_file(changelog_path)

    with open(changelog_path, "r") as f:
        content = f.read()

    # Find the Unreleased section
    unreleased_match = re.search(r"## Unreleased\n(.*?)(?=\n## |$)", content, re.DOTALL)
    if not unreleased_match:
        raise ReleaseError("Could not find '## Unreleased' section in CHANGELOG.md")

    changelog_items = unreleased_match.group(1).strip()

    # Update CHANGELOG.md
    new_header = f"## Version {new_marketing} ({new_project})"
    updated_content = content.replace("## Unreleased", new_header, 1)

    # Add new Unreleased section at the top
    lines = updated_content.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == new_header:
            lines.insert(i, "## Unreleased")
            lines.insert(i + 1, "")
            break

    updated_content = "\n".join(lines)

    with open(changelog_path, "w") as f:
        f.write(updated_content)

    # Don't generate HTML file anymore - we'll embed it directly in appcast.xml
    return changelog_items


def generate_html_from_markdown(markdown_text: str, version: Optional[str] = None) -> str:
    """Convert markdown changelog to HTML using markdown2"""
    # Convert markdown to HTML with useful extras
    html_content = markdown2.markdown(
        markdown_text,
        extras=[
            "fenced-code-blocks",
            "tables",
            "strike",
            "target-blank-links",
            "task_list",
            "code-friendly",
        ],
    )

    # Determine title
    title = f"Release Notes - Version {version}" if version else "Release Notes"

    # Wrap in basic HTML structure
    html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{title}</title>
</head>
<body>
{html_content}
</body>
</html>"""

    return html


def create_signing_xcconfig(archive_dir: Path, team_id: str) -> Path:
    """Create an xcconfig file with code signing settings"""
    xcconfig_content = f"""// Temporary build configuration for release signing
DEVELOPMENT_TEAM = {team_id}
CODE_SIGN_STYLE = Automatic

// Use Apple Development for all targets by default
CODE_SIGN_IDENTITY = Apple Development

// For the export step, xcodebuild will use the Developer ID from the export options plist
"""

    xcconfig_path = archive_dir / "release_signing.xcconfig"
    with open(xcconfig_path, "w") as f:
        f.write(xcconfig_content)

    return xcconfig_path


def build_xcode_archive(
    archive_dir: Path, bundle_identifier: str, rollback_manager: RollbackManager
) -> Path:
    """Build Xcode archive and export the app"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    team_id = os.environ.get("APPLE_TEAM_ID")
    if not team_id:
        raise ReleaseError("APPLE_TEAM_ID environment variable is not set")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        # Create xcconfig file for code signing
        task = progress.add_task("Creating signing configuration...", total=None)
        xcconfig_path = create_signing_xcconfig(archive_dir, team_id)

        # Use the archive directory for build artifacts
        archive_path = archive_dir / f"{CONFIG['app_name']}.xcarchive"

        # Don't track archive directory items for rollback - we want to keep them

        # Build archive
        progress.update(task, description="Building Xcode archive...")

        # Build command with xcbeautify and xcconfig
        xcodebuild_cmd = [
            "xcodebuild",
            "-project",
            CONFIG["xcode_project"],
            "-scheme",
            CONFIG["scheme"],
            "-configuration",
            "Release",
            "-xcconfig",
            str(xcconfig_path),
            "-archivePath",
            str(archive_path),
            "-skipMacroValidation",
            "-skipPackagePluginValidation",
            "archive",
        ]

        # Run xcodebuild piped through xcbeautify
        if VERBOSE:
            console.print(
                f"[dim]Running: {' '.join(xcodebuild_cmd)} | xcbeautify[/dim]"
            )
        xcodebuild_proc = subprocess.Popen(
            xcodebuild_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        xcbeautify_proc = subprocess.Popen(
            ["xcbeautify"],
            stdin=xcodebuild_proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Close xcodebuild's stdout in parent process
        if xcodebuild_proc.stdout:
            xcodebuild_proc.stdout.close()

        # Get output from xcbeautify
        stdout, stderr = xcbeautify_proc.communicate()

        # Wait for xcodebuild to finish
        xcodebuild_proc.wait()

        # Check for errors
        if xcodebuild_proc.returncode != 0 or xcbeautify_proc.returncode != 0:
            if stdout:
                console.print(f"[yellow]stdout:[/yellow] {stdout}")
            if stderr:
                console.print(f"[red]stderr:[/red] {stderr}")
            raise ReleaseError("Build archive failed")

        # Export archive
        progress.update(task, description="Exporting archive...")
        export_path = archive_dir / "export"

        # Don't track export directory for rollback - we want to keep it

        # Create export options plist
        export_options = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>{team_id}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>"""

        export_options_path = archive_dir / "ExportOptions.plist"
        # Don't track ExportOptions.plist for rollback - we want to keep it
        with open(export_options_path, "w") as f:
            f.write(export_options)

        run_command(
            [
                "xcodebuild",
                "-exportArchive",
                "-archivePath",
                str(archive_path),
                "-exportPath",
                str(export_path),
                "-exportOptionsPlist",
                str(export_options_path),
            ]
        )

        # Find the exported app
        app_path = export_path / "Context.app"
        if not app_path.exists():
            raise ReleaseError(f"Exported app not found at {app_path}")

        # Note: Don't re-sign here - we'll sign after cleaning in final location

        return app_path


def clean_and_sign_app(app_path: Path) -> None:
    """Deep clean and sign app for notarization"""
    developer_id = get_developer_id_certificate()

    if not QUIET:
        # Create a tree to show what we're doing
        sign_tree = Tree(f"[bold]Signing {app_path.name}[/bold]")
        sign_tree.add(f"Certificate: {developer_id}")

    # First, check if the entire app is already properly signed
    verify_result = run_command(
        ["codesign", "--verify", "--deep", "--strict", str(app_path)],
        check=False,
        show_output=False,
    )

    if verify_result.returncode == 0:
        # App is properly signed, just clean extended attributes
        if not QUIET:
            status_branch = sign_tree.add("[green]App already signed[/green]")
            status_branch.add("Cleaning extended attributes only")
            console.print(sign_tree)

        # Clean extended attributes without affecting signatures
        run_command(["xattr", "-cr", str(app_path)], show_output=False)

        # Remove .DS_Store and ._* files
        run_command(
            ["find", str(app_path), "-name", ".DS_Store", "-delete"], show_output=False
        )
        run_command(
            ["find", str(app_path), "-name", "._*", "-delete"], show_output=False
        )

        # Verify signature is still valid
        run_command(
            ["codesign", "--verify", "--deep", "--strict", str(app_path)],
            show_output=False,
        )

        return

    # If we get here, the app needs signing
    if not QUIET:
        sign_tree.add("[yellow]App needs signing[/yellow]")
        console.print(sign_tree)

    # Phase 1: Deep clean extended attributes and resource forks
    if not QUIET:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            task = progress.add_task("Cleaning extended attributes...", total=None)

            # Remove all extended attributes recursively
            run_command(["xattr", "-cr", str(app_path)], show_output=False)

            # Remove all .DS_Store files
            run_command(
                ["find", str(app_path), "-name", ".DS_Store", "-delete"],
                show_output=False,
            )

            # Remove ._* files (AppleDouble format files)
            run_command(
                ["find", str(app_path), "-name", "._*", "-delete"], show_output=False
            )

            # Use dot_clean to merge and clean AppleDouble files
            run_command(
                ["dot_clean", "-m", str(app_path)], check=False, show_output=False
            )  # dot_clean might not be available
    else:
        # Just run the commands without progress
        run_command(["xattr", "-cr", str(app_path)], show_output=False)
        run_command(
            ["find", str(app_path), "-name", ".DS_Store", "-delete"], show_output=False
        )
        run_command(
            ["find", str(app_path), "-name", "._*", "-delete"], show_output=False
        )
        run_command(["dot_clean", "-m", str(app_path)], check=False, show_output=False)

    # Phase 2: Sign components in correct order (deepest first)
    frameworks_dir = app_path / "Contents" / "Frameworks"
    if frameworks_dir.exists():
        # Use a set to track already signed paths to avoid signing symlinked content twice
        signed_paths = set()

        # Build list of all bundles to sign, starting with deepest (XPC services) first
        bundles_to_sign = []

        # XPC services are deepest in the hierarchy
        for xpc in frameworks_dir.rglob("*.xpc"):
            # Resolve symlinks to get the real path
            real_path = xpc.resolve()

            # Skip if we've already signed this real path
            if real_path in signed_paths:
                console.print(f"[dim]Skipping XPC service (symlink): {xpc.name}[/dim]")
                continue

            signed_paths.add(real_path)
            bundles_to_sign.append(("XPC service", xpc))

        # Then frameworks
        for framework in frameworks_dir.glob("*.framework"):
            # Resolve symlinks to get the real path
            real_path = framework.resolve()

            # Skip if we've already signed this real path
            if real_path in signed_paths:
                console.print(
                    f"[dim]Skipping framework (symlink): {framework.name}[/dim]"
                )
                continue

            signed_paths.add(real_path)
            bundles_to_sign.append(("framework", framework))

        # Sign all bundles
        if not QUIET and bundles_to_sign:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                sign_task = progress.add_task(
                    "Signing frameworks...", total=len(bundles_to_sign)
                )

                for bundle_type, bundle in bundles_to_sign:
                    progress.update(sign_task, description=f"Signing {bundle.name}...")

                    # Clean this specific bundle before signing
                    run_command(["xattr", "-cr", str(bundle)], show_output=False)

                    # Remove any ._* files in the bundle
                    run_command(
                        ["find", str(bundle), "-name", "._*", "-delete"],
                        check=False,
                        show_output=False,
                    )

                    run_command(
                        [
                            "codesign",
                            "--force",
                            "--sign",
                            developer_id,
                            "--options",
                            "runtime",
                            "--timestamp",
                            str(bundle),
                        ],
                        show_output=False,
                    )

                    progress.advance(sign_task)
        else:
            for bundle_type, bundle in bundles_to_sign:
                # Clean this specific bundle before signing
                run_command(["xattr", "-cr", str(bundle)], show_output=False)
                run_command(
                    ["find", str(bundle), "-name", "._*", "-delete"],
                    check=False,
                    show_output=False,
                )
                run_command(
                    [
                        "codesign",
                        "--force",
                        "--sign",
                        developer_id,
                        "--options",
                        "runtime",
                        "--timestamp",
                        str(bundle),
                    ],
                    show_output=False,
                )

    # Phase 3: Sign the main app
    if not QUIET:
        console.print(f"\n{Icons.PROGRESS} Signing main app bundle...")

    # Final clean before signing the main app
    run_command(["xattr", "-cr", str(app_path)], show_output=False)
    run_command(["xattr", "-c", str(app_path)], show_output=False)
    run_command(
        ["find", str(app_path), "-name", "._*", "-delete"],
        check=False,
        show_output=False,
    )

    # Sign the main app with --deep to ensure everything is signed
    run_command(
        [
            "codesign",
            "--force",
            "--deep",
            "--sign",
            developer_id,
            "--options",
            "runtime",
            "--timestamp",
            str(app_path),
        ],
        show_output=False,
    )

    # Verify the complete signature
    run_command(
        ["codesign", "--verify", "--deep", "--strict", str(app_path)], show_output=False
    )

    if not QUIET:
        console.print(f"{Icons.SUCCESS} App signed successfully")


def get_developer_id_certificate() -> str:
    """Get the Developer ID Application certificate name from the keychain"""
    team_id = os.environ.get("APPLE_TEAM_ID")
    if not team_id:
        raise ReleaseError("APPLE_TEAM_ID environment variable is not set")

    # Query keychain for Developer ID Application certificates
    result = run_command(
        ["security", "find-identity", "-v", "-p", "codesigning"], show_output=False
    )

    # Look for Developer ID Application certificate with matching team ID
    import re

    pattern = rf'"(Developer ID Application: [^"]+\({team_id}\))"'
    match = re.search(pattern, result.stdout)

    if not match:
        raise ReleaseError(
            f"Could not find Developer ID Application certificate for team {team_id}"
        )

    return match.group(1)


def prepare_dmg_contents(app_path: Path, archive_dir: Path) -> Tuple[Path, Path, Path]:
    """Prepare DMG contents by copying app to proper structure"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    # Copy app to archive directory, preserving symlinks
    archive_app_path = archive_dir / f"{CONFIG['app_name']}.app"
    if archive_app_path.exists():
        shutil.rmtree(archive_app_path)
    shutil.copytree(app_path, archive_app_path, symlinks=True)

    # Create a directory structure for DMG contents
    dmg_contents = archive_dir / "dmg_contents"
    if dmg_contents.exists():
        shutil.rmtree(dmg_contents)
    dmg_contents.mkdir()

    # Create product folder inside dmg_contents
    product_folder = dmg_contents / CONFIG["app_name"]
    product_folder.mkdir()

    # Move app into the product folder (shutil.move preserves symlinks)
    final_app_path = product_folder / f"{CONFIG['app_name']}.app"
    shutil.move(str(archive_app_path), str(final_app_path))

    return archive_app_path, dmg_contents, final_app_path


def create_dmg(product_folder: Path, dmg_path: Path) -> None:
    """Create DMG from product folder"""
    # Delete existing DMG if it exists
    if dmg_path.exists():
        if VERBOSE:
            console.print(f"[dim]Removing existing DMG: {dmg_path}[/dim]")
        dmg_path.unlink()

    # Create DMG using the product folder
    run_command(
        [
            "hdiutil",
            "create",
            "-srcfolder",
            str(product_folder),
            "-format",
            "UDBZ",
            str(dmg_path),
        ],
        show_output=VERBOSE,
    )


def sign_dmg(dmg_path: Path) -> None:
    """Sign DMG with Developer ID certificate"""
    # Clean the DMG of any extended attributes before signing
    if VERBOSE:
        console.print(f"[dim]Cleaning DMG extended attributes...[/dim]")
    run_command(["xattr", "-c", str(dmg_path)], show_output=False)

    # Sign the DMG with Developer ID certificate
    developer_id = get_developer_id_certificate()
    if VERBOSE:
        console.print(f"[dim]Using certificate: {developer_id}[/dim]")

    run_command(
        [
            "codesign",
            "--force",
            "--deep",
            "--sign",
            developer_id,
            "--options",
            "runtime",  # Enable hardened runtime for notarization
            str(dmg_path),
        ]
    )


def notarize_dmg(dmg_path: Path, archive_dir: Path) -> None:
    """Submit DMG for notarization and wait for completion"""
    notarytool_path = get_notarytool_path()
    keychain_profile = os.environ.get(
        "APPLE_KEYCHAIN_PROFILE", "App Store Connect Profile"
    )
    notarization_response_path = archive_dir / "NotarizationResponse.plist"

    result = run_command(
        [
            notarytool_path,
            "submit",
            str(dmg_path),
            "--verbose",
            "--keychain-profile",
            keychain_profile,
            "--wait",
            "--timeout",
            "2h",
            "--output-format",
            "plist",
        ]
    )

    # Write the plist output to file
    with open(notarization_response_path, "w") as f:
        f.write(result.stdout)

    # Parse the plist to check notarization status
    import plistlib

    with open(notarization_response_path, "rb") as f:
        notarization_response = plistlib.load(f)

    status = notarization_response.get("status", "Unknown")
    message = notarization_response.get("message", "No message provided")

    # Log full response for debugging
    if VERBOSE:
        console.print(
            f"[dim]Notarization response saved to: {notarization_response_path}[/dim]"
        )

    if status != "Accepted":
        handle_notarization_failure(
            notarization_response, archive_dir, notarytool_path, keychain_profile
        )
        raise ReleaseError(f"Notarization failed with status '{status}': {message}")

    # Staple the notarization
    run_command(["xcrun", "stapler", "staple", str(dmg_path)])


def handle_notarization_failure(
    notarization_response: Dict[str, Any],
    archive_dir: Path,
    notarytool_path: str,
    keychain_profile: str,
) -> None:
    """Handle notarization failure by fetching and displaying detailed logs"""
    status = notarization_response.get("status", "Unknown")
    submission_id = notarization_response.get("id")

    if submission_id and status == "Invalid":
        # Fetch the detailed log
        console.print(
            f"[yellow]Fetching detailed notarization log for submission {submission_id}...[/yellow]"
        )

        log_result = run_command(
            [
                notarytool_path,
                "log",
                submission_id,
                "--keychain-profile",
                keychain_profile,
            ]
        )

        # Save the log to a file
        log_path = archive_dir / "notarization_log.json"
        with open(log_path, "w") as f:
            f.write(log_result.stdout)

        if VERBOSE:
            console.print(f"[dim]Notarization log saved to: {log_path}[/dim]")

        # Try to parse and display key issues
        try:
            import json

            log_data = json.loads(log_result.stdout)

            if "issues" in log_data:
                console.print("\n[red]Notarization issues found:[/red]")
                for issue in log_data["issues"]:
                    severity = issue.get("severity", "unknown")
                    message = issue.get("message", "No message")
                    path = issue.get("path", "Unknown path")
                    console.print(f"  [{severity.upper()}] {path}: {message}")

            # Also check productErrors
            if "productErrors" in log_data:
                console.print("\n[red]Product errors:[/red]")
                for error in log_data["productErrors"]:
                    code = error.get("code", "unknown")
                    description = error.get("userInfo", {}).get(
                        "NSLocalizedDescription", "No description"
                    )
                    console.print(f"  [{code}] {description}")

        except json.JSONDecodeError:
            console.print("[yellow]Could not parse notarization log as JSON[/yellow]")
            console.print(log_result.stdout)


def create_and_notarize_dmg(
    app_path: Path,
    archive_dir: Path,
    marketing_version: str,
    rollback_manager: RollbackManager,
) -> Path:
    """Create DMG and submit for notarization"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    dmg_name = f"{CONFIG['app_name']}_v{marketing_version}.dmg"
    dmg_path = archive_dir / dmg_name

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        # Prepare DMG contents
        task = progress.add_task("Copying app to archive directory...", total=None)
        archive_app_path, dmg_contents, final_app_path = prepare_dmg_contents(
            app_path, archive_dir
        )

        # Clean and re-sign the app in its final location
        progress.update(
            task, description="Cleaning and re-signing app for notarization..."
        )
        clean_and_sign_app(final_app_path)

        # Create DMG
        progress.update(task, description="Creating DMG...")
        product_folder = final_app_path.parent
        create_dmg(product_folder, dmg_path)

        # Sign the DMG
        progress.update(task, description="Signing DMG...")
        sign_dmg(dmg_path)

        # Copy the app back to archive directory (using cp -a to preserve attributes)
        run_command(["cp", "-a", str(final_app_path), str(archive_app_path)])

        # Clean up
        shutil.rmtree(dmg_contents)

        # Submit for notarization
        progress.update(task, description="Submitting for notarization...")
        notarize_dmg(dmg_path, archive_dir)

    console.print(f"[green]✓[/green] DMG created and notarized: {dmg_path}")
    return dmg_path


def sign_update(dmg_path: Path) -> Tuple[str, str]:
    """Sign the update with Sparkle and extract signature info"""
    sign_update_path = Path("scripts/bin/sparkle/sign_update")

    # Check if the sign_update tool exists
    if not sign_update_path.exists():
        raise ReleaseError(f"Sparkle sign_update tool not found at {sign_update_path}")

    # Make sure it's executable
    sign_update_path.chmod(0o755)

    try:
        result = run_command([str(sign_update_path), str(dmg_path)])
    except subprocess.CalledProcessError as e:
        error_output = getattr(e, "stdout", "") or ""
        if "Unable to access required key in the Keychain" in error_output:
            console.print(
                "\n[red]Sparkle signing failed: Unable to access EdDSA key in Keychain[/red]"
            )

            # Check for specific error codes
            if "-60008" in error_output:
                console.print("\n[yellow]Error -60008: Authentication failed[/yellow]")
                console.print("This usually means:")
                console.print(
                    "  • The keychain containing the Sparkle key is not the default keychain"
                )
                console.print("  • The keychain was locked again after unlocking")
                console.print("\nTry:")
                console.print(
                    "1. Check which keychain contains your Sparkle EdDSA key in Keychain Access"
                )
                console.print(
                    "2. If it's not in the default keychain, you may need to:"
                )
                console.print("   - Set that keychain as default temporarily")
                console.print("   - Or move the key to your default keychain")
                console.print(
                    "3. Make sure the key's Access Control allows 'sign_update' to access it"
                )
            elif "-25300" in error_output:
                console.print("\n[yellow]Error -25300: Item not found[/yellow]")
                console.print(
                    "The Sparkle EdDSA private key was not found in any unlocked keychain."
                )
                console.print(
                    "\nMake sure you have generated a Sparkle EdDSA key pair and imported the private key."
                )
            else:
                console.print("\n[yellow]To fix this issue:[/yellow]")
                console.print("1. Open Keychain Access.app")
                console.print(
                    "2. Find your Sparkle EdDSA private key (usually named 'Private key for signing Sparkle updates')"
                )
                console.print(
                    "3. Double-click the key and go to the 'Access Control' tab"
                )
                console.print("4. Either:")
                console.print(
                    "   - Select 'Allow all applications to access this item'"
                )
                console.print(
                    "   - Or add 'sign_update' to the list of allowed applications"
                )
                console.print(
                    "5. Click 'Save Changes' and enter your password when prompted"
                )

            raise ReleaseError("Sparkle signing failed due to Keychain access issue")
        raise

    # Parse the output to extract signature and length
    output = result.stdout.strip()

    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', output)
    len_match = re.search(r'length="(\d+)"', output)

    if not sig_match or not len_match:
        raise ReleaseError(f"Could not parse sign_update output: {output}")

    return sig_match.group(1), len_match.group(1)


def update_appcast(
    marketing_version: str,
    project_version: int,
    signature: str,
    length: str,
    changelog_items: str,
    rollback_manager: RollbackManager,
) -> None:
    """Update appcast.xml with new release information"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    appcast_path = Path("appcast.xml")

    # Backup appcast.xml before modifying
    rollback_manager.backup_file(appcast_path)

    # Parse existing appcast
    parser = etree.XMLParser(remove_blank_text=True)
    tree = etree.parse(str(appcast_path), parser)
    root = tree.getroot()

    # Find the channel element
    channel = root.find(".//channel")
    if channel is None:
        raise ReleaseError("Could not find channel element in appcast.xml")

    # Create new item
    new_item = etree.Element("item")

    # Add title
    title = etree.SubElement(new_item, "title")
    title.text = f"Version {marketing_version} ({project_version})"

    # Add link
    link = etree.SubElement(new_item, "link")
    link.text = CONFIG["website_url"]

    # Add version info
    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    etree.SubElement(new_item, f"{{{sparkle_ns}}}version").text = str(project_version)
    etree.SubElement(
        new_item, f"{{{sparkle_ns}}}shortVersionString"
    ).text = marketing_version

    # Add minimum system version
    min_sys_version = CONFIG.get("minimum_system_version", "15.0")
    etree.SubElement(
        new_item, f"{{{sparkle_ns}}}minimumSystemVersion"
    ).text = min_sys_version

    # Add description with HTML release notes in CDATA
    description = etree.SubElement(new_item, "description")
    # Convert markdown to HTML
    html_content = markdown2.markdown(
        changelog_items,
        extras=[
            "fenced-code-blocks",
            "tables",
            "strike",
            "target-blank-links",
            "task_list",
            "code-friendly",
        ],
    )
    # Wrap in CDATA
    description.text = etree.CDATA(html_content)

    # Add publication date
    pub_date = etree.SubElement(new_item, "pubDate")
    pub_date.text = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    # Add enclosure
    enclosure = etree.SubElement(new_item, "enclosure")
    enclosure.set(
        "url",
        f"https://github.com/{CONFIG['github_owner']}/{CONFIG['github_repo']}/releases/download/v{marketing_version}/{CONFIG['app_name']}_v{marketing_version}.dmg",
    )
    enclosure.set(f"{{{sparkle_ns}}}edSignature", signature)
    enclosure.set("length", length)
    enclosure.set("type", "application/octet-stream")

    # Insert new item after the last <title> element and before first <item>
    insert_index = 0
    for i, child in enumerate(channel):
        if (
            child.tag == "title"
            or child.tag == "link"
            or child.tag == "description"
            or child.tag == "language"
        ):
            insert_index = i + 1
        elif child.tag == "item":
            break

    channel.insert(insert_index, new_item)

    # Write updated appcast
    tree.write(
        str(appcast_path), encoding="utf-8", xml_declaration=True, pretty_print=True
    )


def create_git_commit_and_tag(marketing_version: str, changelog_items: str) -> Tuple[str, bool]:
    """Create git commit and annotated tag
    
    Returns:
        Tuple of (tag_name, pushed_to_github)
    """
    pushed = False
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        # Add all changed files
        task = progress.add_task("Creating git commit...", total=None)
        run_command(["git", "add", "-A"])

        # Create commit
        commit_message = f"Publish v{marketing_version}"
        run_command(["git", "commit", "-m", commit_message])

        # Create annotated tag
        progress.update(task, description="Creating git tag...")
        tag_name = f"v{marketing_version}"
        run_command(["git", "tag", "-a", tag_name, "-m", changelog_items])

        # Push commit and tag - POINT OF NO RETURN
        # After this point, rollback is not possible as changes are permanent on GitHub
        progress.update(task, description="Pushing to remote...")
        run_command(["git", "push", "origin", "main"])
        run_command(["git", "push", "origin", tag_name])
        pushed = True

    console.print(
        f"[green]✓[/green] Created and pushed commit and tag for v{marketing_version}"
    )
    return tag_name, pushed


def create_dsyms_zip(archive_dir: Path, dmg_path: Path) -> Optional[Path]:
    """Create a ZIP file of the dSYMs directory"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    # Find dSYMs directory
    dsyms_path = archive_dir / f"{CONFIG['app_name']}.xcarchive" / "dSYMs"
    if not dsyms_path.exists():
        if not QUIET:
            console.print(
                f"{Icons.WARNING} dSYMs directory not found, skipping dSYMs ZIP creation"
            )
        return None

    # Create ZIP filename based on DMG name
    dmg_name = dmg_path.stem  # e.g., "Context_v1.2.3"
    dsyms_zip_name = f"{dmg_name}_dSYMs.zip"
    dsyms_zip_path = archive_dir / dsyms_zip_name

    if not QUIET:
        console.print(f"{Icons.PROGRESS} Creating dSYMs ZIP archive...")

    # Use ditto to create the ZIP file
    run_command(
        ["ditto", "-c", "-k", "--keepParent", str(dsyms_path), str(dsyms_zip_path)],
        show_output=VERBOSE,
    )

    # Get ZIP size for logging
    zip_size_mb = dsyms_zip_path.stat().st_size / (1024 * 1024)
    if not QUIET:
        console.print(
            f"{Icons.SUCCESS} Created dSYMs ZIP: {dsyms_zip_name} ({zip_size_mb:.1f} MB)"
        )

    return dsyms_zip_path


def create_github_release(
    tag_name: str,
    dmg_path: Path,
    marketing_version: str,
    dsyms_zip_path: Optional[Path],
) -> str:
    """Create GitHub release with DMG and optional dSYMs ZIP"""
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task("Creating GitHub release...", total=None)

        # Build the command with DMG
        cmd = ["gh", "release", "create", tag_name, str(dmg_path)]

        # Add dSYMs ZIP if available
        if dsyms_zip_path and dsyms_zip_path.exists():
            cmd.append(str(dsyms_zip_path))
            if not QUIET:
                progress.update(
                    task, description="Creating GitHub release with DMG and dSYMs..."
                )

        # Add remaining arguments
        cmd.extend(
            [
                "--latest",
                "--notes-from-tag",
                "--verify-tag",
                "--title",
                f"Version {marketing_version}",
            ]
        )

        result = run_command(cmd)

        # Extract release URL from output
        release_url = None
        for line in result.stdout.strip().split("\n"):
            if line.startswith("https://github.com/"):
                release_url = line
                break

        if not release_url:
            raise ReleaseError("Could not find release URL in gh output")

    return release_url


def upload_dsyms_to_sentry(archive_dir: Path, sentry_org: str, sentry_project: str) -> None:
    """Upload dSYMs to Sentry for crash reporting"""
    assert CONFIG is not None, "CONFIG must be initialized"
    
    # Check if sentry-cli is available
    if shutil.which("sentry-cli") is None:
        console.print("[yellow]sentry-cli not found, skipping dSYM upload[/yellow]")
        return

    # Check for auth token
    sentry_auth_token = os.environ.get("SENTRY_AUTH_TOKEN")
    if not sentry_auth_token:
        console.print(
            "[yellow]SENTRY_AUTH_TOKEN not set, skipping dSYM upload[/yellow]"
        )
        return

    # Find dSYMs directory
    dsyms_path = archive_dir / f"{CONFIG['app_name']}.xcarchive" / "dSYMs"
    if not dsyms_path.exists():
        console.print(
            f"[yellow]dSYMs directory not found at {dsyms_path}, skipping upload[/yellow]"
        )
        return

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task("Uploading dSYMs to Sentry...", total=None)

        try:
            run_command(
                [
                    "sentry-cli",
                    "debug-files",
                    "upload",
                    "--auth-token",
                    sentry_auth_token,
                    "--org",
                    sentry_org,
                    "--project",
                    sentry_project,
                    str(dsyms_path),
                ]
            )
            console.print("[green]✓[/green] Successfully uploaded dSYMs to Sentry")
        except Exception as e:
            console.print(f"[yellow]Failed to upload dSYMs to Sentry: {e}[/yellow]")
            console.print(
                "[yellow]This is not a critical error, continuing...[/yellow]"
            )


def show_release_summary(
    marketing_version: str,
    project_version: int,
    dmg_path: Path,
    release_url: str,
    start_time: float,
    skipped_items: List[str],
) -> None:
    """Show a beautiful release summary dashboard"""
    if QUIET:
        console.print(
            f"\n{Icons.SUCCESS} Release v{marketing_version} published: {release_url}"
        )
        return

    # Calculate duration
    duration = time.time() - start_time
    minutes = int(duration // 60)
    seconds = int(duration % 60)

    # Get DMG size
    dmg_size_mb = dmg_path.stat().st_size / (1024 * 1024)

    # Create the main panel
    summary_content = f"""
[bold green]Release v{marketing_version} Published Successfully![/bold green]

[bold]Version:[/bold] {marketing_version} (Build {project_version})
[bold]DMG Size:[/bold] {dmg_size_mb:.1f} MB
[bold]Location:[/bold] {dmg_path}
[bold]Duration:[/bold] {minutes}m {seconds}s

[bold]GitHub Release:[/bold]
[link={release_url}]{release_url}[/link]
"""

    if skipped_items:
        summary_content += "\n[bold yellow]Skipped:[/bold yellow]\n"
        for item in skipped_items:
            summary_content += f"  • {item}\n"

    panel = Panel(
        summary_content.strip(),
        title="[bold]🎉 Release Summary[/bold]",
        border_style="green",
        padding=(1, 2),
        expand=False,
    )

    console.print()
    console.print(panel)
    console.print()


def verify_release(
    dmg_path: Path, marketing_version: str, project_version: int
) -> None:
    """Verify the release artifacts"""
    if not QUIET:
        console.print()
        console.rule("[bold blue]Release Verification[/bold blue]")

    verification_results = []

    # Verify DMG exists
    if not dmg_path.exists():
        raise ReleaseError(f"DMG not found at {dmg_path}")

    dmg_size_mb = dmg_path.stat().st_size / (1024 * 1024)
    verification_results.append((Icons.SUCCESS, f"DMG size: {dmg_size_mb:.1f} MB"))

    # Verify DMG is signed
    result = run_command(
        ["codesign", "--verify", str(dmg_path)], check=False, show_output=False
    )
    if result.returncode != 0:
        raise ReleaseError("DMG signature verification failed")

    verification_results.append((Icons.SUCCESS, "DMG signature verified"))

    # Verify DMG is notarized
    result = run_command(
        [
            "spctl",
            "-a",
            "-t",
            "open",
            "--context",
            "context:primary-signature",
            "-v",
            str(dmg_path),
        ],
        check=False,
        show_output=False,
    )
    if result.returncode != 0:
        verification_results.append(
            (
                Icons.WARNING,
                "DMG notarization check failed (may be normal if run immediately)",
            )
        )
    else:
        verification_results.append((Icons.SUCCESS, "DMG notarization verified"))

    # No longer verify release notes files since we embed them in appcast.xml

    # Verify appcast was updated
    appcast_path = Path("appcast.xml")
    if appcast_path.exists():
        content = appcast_path.read_text()
        if f"Version {marketing_version} ({project_version})" not in content:
            verification_results.append(
                (Icons.WARNING, "Appcast may not have been updated correctly")
            )
        else:
            verification_results.append((Icons.SUCCESS, "Appcast updated"))

    if not QUIET:
        # Create verification panel
        verification_content = "\n".join(
            [f"{icon} {msg}" for icon, msg in verification_results]
        )

        panel = Panel(
            verification_content,
            title="[bold]Verification Results[/bold]",
            border_style="blue",
            padding=(1, 2),
        )

        console.print(panel)
        console.print()


def main() -> None:
    """Main entry point"""
    global CONFIG, VERBOSE, QUIET, DEBUG

    # Track start time
    start_time = time.time()

    # Track what was skipped
    skipped_items = []

    # Initialize rollback manager
    rollback_manager = RollbackManager()
    
    # Track if we've pushed to GitHub (point of no return)
    pushed_to_github = False
    
    # Initialize version variables (for error handling)
    new_marketing = None
    new_project = None

    try:
        # Parse arguments first to get config path
        args = parse_arguments()

        # Set verbosity flags
        VERBOSE = args.verbose
        QUIET = args.quiet
        DEBUG = args.debug

        # Load configuration
        CONFIG = load_config(args.config)

        # Now show the banner with the app name from config
        if not QUIET:
            console.print(
                Panel.fit(
                    f"[bold cyan]{CONFIG['app_name']} Release Automation[/bold cyan]\n"
                    "Building and publishing a new release",
                    border_style="cyan",
                )
            )

        # Run validation tasks sequentially
        if not QUIET:
            console.print()
            console.rule("[bold blue]Validation Phase[/bold blue]")

        validation_tasks = [
            ("Validating tools", validate_tools, ()),
            ("Validating environment", validate_environment, ()),
            ("Running pre-flight checks", preflight_checks, ()),
        ]

        try:
            tool_results, env_vars, warnings = run_parallel_tasks(
                validation_tasks, "Running validation checks"
            )
        except Exception as e:
            # If any validation failed, show the error
            raise ReleaseError(f"Validation failed: {e}")

        # Show pre-release checklist
        if not show_pre_release_checklist(warnings):
            raise ReleaseError("Release cancelled by user")

        # Get current versions
        if not QUIET:
            console.print()
            console.rule("[bold blue]Version Management[/bold blue]")

        project_path = Path(CONFIG["xcode_project"]) / "project.pbxproj"
        current_project, current_marketing = get_current_versions(
            project_path, CONFIG["bundle_identifier"]
        )

        # Calculate new versions
        new_project, new_marketing = increment_versions(
            current_project, current_marketing, args.version_type
        )

        # Show version table
        show_version_table(
            current_marketing,
            current_project,
            new_marketing,
            new_project,
            args.version_type,
        )

        # Update project versions (unless skipping)
        if args.version_type == "skip":
            if not QUIET:
                console.print(f"{Icons.WARNING} Skipping version number update")
            skipped_items.append("Version number update")
        else:
            with console.status("Updating version numbers..."):
                update_project_versions(
                    project_path,
                    CONFIG["bundle_identifier"],
                    new_project,
                    new_marketing,
                    rollback_manager,
                )
            if not QUIET:
                console.print(f"{Icons.SUCCESS} Updated version numbers")

        # Process changelog
        if not QUIET:
            console.print()
            console.rule("[bold blue]Changelog Processing[/bold blue]")

        with console.status("Processing changelog..."):
            changelog_items = process_changelog(
                new_project, new_marketing, rollback_manager
            )

        if not QUIET:
            console.print(
                f"{Icons.SUCCESS} Processed changelog and generated release notes"
            )

        # Show release notes preview
        show_release_notes_preview(changelog_items, new_marketing)

        # Build Xcode archive
        if not QUIET:
            console.print()
            console.rule("[bold blue]Building Release[/bold blue]")

        app_path = build_xcode_archive(
            args.archive_path, CONFIG["bundle_identifier"], rollback_manager
        )
        if not QUIET:
            console.print(f"{Icons.SUCCESS} Built Xcode archive")

        # Create and notarize DMG
        if not QUIET:
            console.print()
            console.rule("[bold blue]DMG Creation & Notarization[/bold blue]")

        dmg_path = create_and_notarize_dmg(
            app_path, args.archive_path, new_marketing, rollback_manager
        )

        # Sign update and update appcast (unless skipped)
        if args.skip_sparkle:
            if not QUIET:
                console.print(
                    f"{Icons.WARNING} Skipping Sparkle signing and appcast update (--skip-sparkle flag)"
                )
            skipped_items.append("Sparkle signing")
            skipped_items.append("Appcast update")
        else:
            if not QUIET:
                console.print()
                console.rule("[bold blue]Sparkle Update Signing[/bold blue]")

            # Unlock keychain for Sparkle signing
            if not unlock_keychain():
                raise ReleaseError("Failed to unlock keychain for Sparkle signing")

            # Sign update
            with console.status("Signing update with Sparkle..."):
                signature, length = sign_update(dmg_path)
            if not QUIET:
                console.print(f"{Icons.SUCCESS} Signed update")

            # Update appcast
            with console.status("Updating appcast.xml..."):
                update_appcast(
                    new_marketing, new_project, signature, length, changelog_items, rollback_manager
                )
            if not QUIET:
                console.print(f"{Icons.SUCCESS} Updated appcast.xml")

        # Verify the release artifacts before committing
        verify_release(dmg_path, new_marketing, new_project)

        # Create git commit and tag
        if not QUIET:
            console.print()
            console.rule("[bold blue]Git & GitHub Release[/bold blue]")

        tag_name, pushed_to_github = create_git_commit_and_tag(new_marketing, changelog_items)

        # Create dSYMs ZIP for GitHub release
        dsyms_zip_path = create_dsyms_zip(args.archive_path, dmg_path)

        # Create GitHub release
        release_url = create_github_release(
            tag_name, dmg_path, new_marketing, dsyms_zip_path
        )

        # Upload dSYMs to Sentry if configured
        if args.sentry_org and args.sentry_project:
            if not QUIET:
                console.print()
                console.rule("[bold blue]Post-Release Tasks[/bold blue]")
            upload_dsyms_to_sentry(
                args.archive_path, args.sentry_org, args.sentry_project
            )
        else:
            if not QUIET:
                console.print(
                    f"\n{Icons.INFO} Skipping Sentry dSYM upload (--sentry-org and --sentry-project not provided)"
                )
            skipped_items.append("Sentry dSYM upload")

        # Show release summary
        show_release_summary(
            new_marketing, new_project, dmg_path, release_url, start_time, skipped_items
        )

    except ReleaseError as e:
        if pushed_to_github:
            # Don't rollback if we've already pushed to GitHub
            version_str = f"v{new_marketing}" if new_marketing else "version"
            if not QUIET:
                error_panel = Panel(
                    f"[bold red]Release Partially Completed[/bold red]\n\n"
                    f"The commit and tag have been pushed to GitHub ({version_str}).\n"
                    f"However, the following error occurred:\n\n{e}\n\n"
                    f"[yellow]Manual intervention may be required to complete the release.[/yellow]",
                    border_style="red",
                    padding=(1, 2),
                )
                console.print()
                console.print(error_panel)
            else:
                console.print(f"\n{Icons.ERROR} Error after pushing to GitHub: {e}")
                console.print(f"{Icons.WARNING} The commit and tag {version_str} have been pushed.")
                console.print(f"{Icons.WARNING} Manual intervention may be required.")
        else:
            rollback_manager.rollback()
            if not QUIET:
                error_panel = Panel(
                    f"[bold red]Release Failed[/bold red]\n\n{e}",
                    border_style="red",
                    padding=(1, 2),
                )
                console.print()
                console.print(error_panel)
            else:
                console.print(f"\n{Icons.ERROR} Error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        if pushed_to_github:
            version_str = f"v{new_marketing}" if new_marketing else "version"
            if not QUIET:
                console.print(f"\n{Icons.WARNING} Release interrupted after pushing to GitHub!")
                console.print(f"{Icons.WARNING} The commit and tag {version_str} have been pushed.")
                console.print(f"{Icons.WARNING} Manual intervention may be required to complete the release.")
        else:
            rollback_manager.rollback()
            if not QUIET:
                console.print(f"\n{Icons.WARNING} Release cancelled by user")
        sys.exit(1)
    except Exception as e:
        if pushed_to_github:
            version_str = f"v{new_marketing}" if new_marketing else "version"
            if not QUIET:
                console.print(f"\n{Icons.ERROR} Unexpected error after pushing to GitHub: {e}")
                console.print(f"{Icons.WARNING} The commit and tag {version_str} have been pushed.")
                console.print(f"{Icons.WARNING} Manual intervention may be required to complete the release.")
            if DEBUG:
                import traceback
                traceback.print_exc()
            else:
                console.print("\nRun with --debug flag for full stack trace")
        else:
            rollback_manager.rollback()
            if not QUIET:
                console.print(f"\n{Icons.ERROR} Unexpected error: {e}")
            if DEBUG:
                import traceback
                traceback.print_exc()
            else:
                console.print("\nRun with --debug flag for full stack trace")
        sys.exit(1)


if __name__ == "__main__":
    main()
