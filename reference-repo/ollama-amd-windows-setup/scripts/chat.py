#!/usr/bin/env python3
"""
Simple Python chat client using Ollama API with streaming response support.

Usage:
    python chat.py
    python chat.py --model phi3:mini
    python chat.py --model llama3.1:8b --system "You are a helpful assistant."

Commands (in chat):
    /quit           - Exit chat
    /clear          - Clear conversation history
    /model <name>   - Switch to another model
    /help           - Show commands

Requires Ollama server running on localhost:11434.
Uses requests library (pure Python, no llama_cpp dependency).
"""

import argparse
import json
import sys
from typing import List, Dict, Any


class OllamaChatClient:
    """Simple Ollama chat client with streaming support."""

    def __init__(self, model: str, system_prompt: str = "", api_url: str = "http://localhost:11434"):
        """
        Initialize chat client.

        Args:
            model: Model name (e.g., "llama3.1:8b")
            system_prompt: System prompt to set context
            api_url: Base URL for Ollama API
        """
        self.model = model
        self.system_prompt = system_prompt
        self.api_url = api_url
        self.messages: List[Dict[str, str]] = []

        try:
            import requests
            self.requests = requests
        except ImportError:
            print("Error: 'requests' not installed")
            print("Install: pip install requests")
            sys.exit(1)

    def chat(self, user_message: str) -> str:
        """
        Send a message and get a streaming response.

        Args:
            user_message: User message

        Returns:
            Full response text
        """
        # Add message to history
        self.messages.append({"role": "user", "content": user_message})

        endpoint = f"{self.api_url}/api/chat"
        payload = {
            "model": self.model,
            "messages": self.messages,
            "stream": True,
        }

        if self.system_prompt:
            # System prompt in first message context (Ollama may handle it differently)
            payload["system"] = self.system_prompt

        try:
            response = self.requests.post(
                endpoint,
                json=payload,
                stream=True,
                timeout=300
            )
            response.raise_for_status()

            full_response = ""
            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line)
                        message_chunk = chunk.get("message", {})
                        content = message_chunk.get("content", "")
                        if content:
                            full_response += content
                            print(content, end="", flush=True)
                    except json.JSONDecodeError:
                        continue

            print()  # Newline after response
            self.messages.append({"role": "assistant", "content": full_response})
            return full_response

        except self.requests.exceptions.ConnectionError:
            print("\n✗ Error: Cannot connect to Ollama API")
            print("  Make sure Ollama is running: ollama serve")
            sys.exit(1)
        except self.requests.exceptions.Timeout:
            print("\n✗ Error: Request timeout")
            sys.exit(1)
        except self.requests.exceptions.RequestException as e:
            print(f"\n✗ Error: {e}")
            sys.exit(1)

    def clear_history(self):
        """Clear conversation history."""
        self.messages = []
        print("Conversation history cleared.")

    def switch_model(self, new_model: str):
        """Switch to a different model."""
        self.model = new_model
        print(f"Switched to model: {self.model}")

    def show_help(self):
        """Show available commands."""
        print("\nAvailable commands:")
        print("  /quit           - Exit chat")
        print("  /clear          - Clear conversation history")
        print("  /model <name>   - Switch to another model")
        print("  /help           - Show this help")
        print()


def main():
    """Parse args and run chat loop."""
    parser = argparse.ArgumentParser(
        description="Chat with Ollama models"
    )
    parser.add_argument(
        "--model",
        default="llama3.1:8b",
        help="Model to use (default: llama3.1:8b)",
    )
    parser.add_argument(
        "--system",
        default="",
        help="System prompt to set context",
    )
    parser.add_argument(
        "--url",
        default="http://localhost:11434",
        help="Ollama API base URL (default: http://localhost:11434)",
    )

    args = parser.parse_args()

    # Initialize client
    client = OllamaChatClient(
        model=args.model,
        system_prompt=args.system,
        api_url=args.url
    )

    # Welcome message
    print("=" * 60)
    print("Ollama Chat Client")
    print("=" * 60)
    print(f"Model: {client.model}")
    if client.system_prompt:
        print(f"System: {client.system_prompt[:50]}...")
    print("\nType your message (or /help for commands)")
    print("-" * 60)
    print()

    # Chat loop
    while True:
        try:
            user_input = input("You: ").strip()

            if not user_input:
                continue

            # Handle commands
            if user_input.startswith("/"):
                cmd_parts = user_input.split(maxsplit=1)
                cmd = cmd_parts[0].lower()

                if cmd == "/quit":
                    print("\nGoodbye!")
                    sys.exit(0)

                elif cmd == "/clear":
                    client.clear_history()

                elif cmd == "/model":
                    if len(cmd_parts) > 1:
                        new_model = cmd_parts[1]
                        client.switch_model(new_model)
                    else:
                        print("Usage: /model <model_name>")

                elif cmd == "/help":
                    client.show_help()

                else:
                    print(f"Unknown command: {cmd}")
                    print("Type /help for available commands")

                continue

            # Send message and get response
            print(f"\n{client.model}: ", end="")
            client.chat(user_input)
            print()

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            sys.exit(0)
        except EOFError:
            print("\n\nGoodbye!")
            sys.exit(0)


if __name__ == "__main__":
    main()
