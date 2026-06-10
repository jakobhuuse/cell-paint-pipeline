"""Smoke tests: the CLI loads and its commands expose help without error."""

from typer.testing import CliRunner

from cytopipe.cli import app

runner = CliRunner()


def test_root_help_lists_commands():
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "convert" in result.output
    assert "bridge" in result.output


def test_convert_help():
    result = runner.invoke(app, ["convert", "--help"])
    assert result.exit_code == 0


def test_bridge_help():
    result = runner.invoke(app, ["bridge", "--help"])
    assert result.exit_code == 0
