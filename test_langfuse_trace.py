#!/usr/bin/env python3
"""
Test script to send traces to Langfuse
"""
import requests
import json

# Langfuse API configuration
host = "http://localhost:3001"
public_key = "pk-lf-e4267bc2-55e5-4483-8a5b-9b8e215f5ab9"
secret_key = "sk-lf-e6da0dc7-5fdc-4a45-a33d-ea7aa6589502"

# Create a trace
trace_response = requests.post(
    f"{host}/api/public/traces",
    headers={
        "Authorization": f"Bearer {secret_key}",
        "Content-Type": "application/json"
    },
    json={
        "name": "test-agent-execution",
        "userId": "test-user",
        "metadata": {
            "agent": "test-agent",
            "environment": "development"
        }
    }
)

if trace_response.status_code == 200:
    trace_data = trace_response.json()
    trace_id = trace_data.get("id")
    
    print(f"✅ Trace created: {trace_id}")
    
    # Create a generation
    generation_response = requests.post(
        f"{host}/api/public/generations",
        headers={
            "Authorization": f"Bearer {secret_key}",
            "Content-Type": "application/json"
        },
        json={
            "traceId": trace_id,
            "name": "llm-call",
            "model": "azure-openai",
            "modelParameters": {"temperature": 0.7, "max_tokens": 100},
            "input": {"prompt": "What is artificial intelligence?"},
            "output": {"text": "Artificial intelligence is the simulation of human intelligence processes by machines."},
            "usage": {
                "promptTokens": 10,
                "completionTokens": 15,
                "totalTokens": 25
            }
        }
    )
    
    print(f"✅ Generation created: {generation_response.status_code}")
    
    # Create a score
    score_response = requests.post(
        f"{host}/api/public/scores",
        headers={
            "Authorization": f"Bearer {secret_key}",
            "Content-Type": "application/json"
        },
        json={
            "traceId": trace_id,
            "name": "relevance",
            "value": 0.95,
            "comment": "Highly relevant response"
        }
    )
    
    print(f"✅ Score created: {score_response.status_code}")
    
    print("\n🎉 Trace sent to Langfuse successfully!")
    print(f"   Check http://localhost:3001/traces to see your data")
else:
    print(f"❌ Error creating trace: {trace_response.status_code}")
    print(trace_response.text)

