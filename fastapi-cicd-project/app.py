
from fastapi import FastAPI
from datetime import datetime

app = FastAPI(title="Jenkins CI/CD Demo")

@app.get("/")
def home():
    return {
        "message": "Hello! Jenkins CI/CD is working!",
        "application": "FastAPI",
        "status": "Running",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
def health():
    return {
        "status": "healthy"
    }

@app.get("/students")
def students():
    return {
        "students": [
            "Rahul",
            "Priya",
            "Amit",
            "Sneha"
        ]
    }
