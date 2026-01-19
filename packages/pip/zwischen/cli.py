"""Command-line interface for Zwischen."""

import click
from .scanner import scan as do_scan
from .init import init as do_init
from .doctor import doctor as do_doctor


@click.group()
@click.version_option()
def main():
    """AI-augmented security scanning for vibe coders."""
    pass


@main.command()
def init():
    """Initialize Zwischen in your project."""
    do_init()


@main.command()
@click.option("--ai", help="AI provider (ollama, openai, anthropic)")
@click.option("--api-key", help="API key for AI provider")
@click.option("--format", "output_format", default="terminal", help="Output format (terminal, json)")
@click.option("--pre-push", is_flag=True, help="Pre-push mode (compact output)")
def scan(ai, api_key, output_format, pre_push):
    """Run security scan."""
    do_scan(ai=ai, api_key=api_key, output_format=output_format, pre_push=pre_push)


@main.command()
def doctor():
    """Check if required tools are installed."""
    do_doctor()


if __name__ == "__main__":
    main()
