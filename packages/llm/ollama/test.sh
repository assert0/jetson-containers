#!/usr/bin/env bash
set -x

echo "TESTING OLLAMA"

#ollama --version

ollama_ready() {
    python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:11434/api/version", timeout=1)' >/dev/null 2>&1
}

if ! ollama_ready; then
    OLLAMA_LLM_LIBRARY=cuda_v${CUDA_VERSION_MAJOR} OLLAMA_DEBUG=1 /bin/ollama serve &
    OLLAMA_PID=$!
    trap 'kill "$OLLAMA_PID" 2>/dev/null || true; wait "$OLLAMA_PID" 2>/dev/null || true' EXIT

    for ((attempt=0; attempt<60; attempt++)); do
        if ollama_ready; then
            break
        fi
        if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
            echo "ollama server exited before becoming ready"
            exit 1
        fi
        sleep 1
    done
fi

if ! ollama_ready; then
    echo "ollama server did not become ready within 60 seconds"
    exit 1
fi

# run the test
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
python3 $SCRIPT_DIR/test.py
