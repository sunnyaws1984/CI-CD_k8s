# CI-CD_k8s

A beginner-friendly sample project for learning **Continuous Integration
and Continuous Delivery (CI/CD)** with Kubernetes, Jenkins, Docker, and
FastAPI.

This repository is intended as a hands-on learning lab. It demonstrates
how to install Jenkins in a Kubernetes cluster, access the Jenkins
dashboard, and run a simple FastAPI application locally before
connecting the application to a CI/CD pipeline.

## Learning objectives

By completing this lab, you will learn how to:

-   Install Jenkins on Kubernetes using the provided installation
    script.
-   Use `kubectl` to interact with Kubernetes resources.
-   Access a Jenkins service locally using port forwarding.
-   Install Python application dependencies.
-   Run and test a FastAPI application.
-   Build toward an automated CI/CD workflow.

## Architecture

The intended workflow for the complete CI/CD lab is:

``` text
Developer
   |
   | Push code
   v
GitHub repository
   |
   | Jenkins pipeline
   v
Build and test application
   |
   | Build container image
   v
Container registry
   |
   | Deploy updated image
   v
Kubernetes cluster
   |
   v
FastAPI application
```

> **Note:** The commands below install Jenkins and run FastAPI locally.
> A complete automated pipeline also requires a configured
> `Jenkinsfile`, container image build/push steps, registry credentials,
> and Kubernetes deployment manifests.

## Prerequisites

Install and configure the following tools:

-   Docker Desktop with Kubernetes enabled, or another working
    Kubernetes cluster.
-   `kubectl`
-   Helm
-   Python 3
-   Git and Git Bash (for Windows users)

Verify that Kubernetes is available:

``` bash
kubectl cluster-info
kubectl get nodes
```

If these commands fail, first check that Docker Desktop is running and
its Kubernetes cluster is enabled.

## Repository structure

A typical repository layout is:

``` text
CI-CD_k8s/
├── install-jenkins.sh
└── fastapi-cicd-project/
    ├── app.py
    ├── requirements.txt
    ├── Dockerfile
    ├── Jenkinsfile
    ├── .dockerignore
    └── k8s/
        ├── deployment.yaml
        └── service.yaml
```

The FastAPI project files may be added as you progress through the lab.

## Step 1: Install Jenkins on Kubernetes

From the repository root, run:

``` bash
sh -x install-jenkins.sh
```

The `-x` option prints each shell command as the script executes. This
is useful for learning and troubleshooting.

Check that the Jenkins resources have been created:

``` bash
kubectl get pods -n jenkins
kubectl get services -n jenkins
```

Wait until the Jenkins pod is ready before continuing.

## Step 2: Access the Jenkins dashboard

Run:

``` bash
kubectl port-forward svc/jenkins 8080:8080 -n jenkins
```

Keep this terminal window open while using Jenkins. Port forwarding
stops when the command is interrupted or the terminal closes.

Open the Jenkins dashboard:

<http://localhost:8080>

To stop port forwarding, press `Ctrl+C`.

### Why use port forwarding?

A Kubernetes `NodePort` service does not always become reachable through
`localhost` automatically. This can happen with local Kubernetes
environments that run nodes inside containers or virtual machines.

`kubectl port-forward` creates a direct local connection to the Jenkins
service and is a convenient way to access Jenkins during this lab.

## Step 3: Run the FastAPI application

Open a **new terminal** and move into the application directory:

``` bash
cd fastapi-cicd-project
```

Install the Python dependencies:

``` bash
python -m pip install -r requirements.txt
```

Start the application:

``` bash
python -m uvicorn app:app --reload
```

Using `python -m uvicorn` runs Uvicorn through the active Python
interpreter and can avoid PATH-related issues where the `uvicorn`
command is not found.

The `--reload` option automatically restarts the development server when
you make code changes. It is intended for local development, not
production deployment.

### Test the application

Open these URLs in your browser:

  -----------------------------------------------------------------------
  URL                                 Purpose
  ----------------------------------- -----------------------------------
  <http://127.0.0.1:8000>             Application home page

  <http://127.0.0.1:8000/docs>        Interactive Swagger API
                                      documentation

  <http://127.0.0.1:8000/health>      Health-check endpoint
  -----------------------------------------------------------------------

Keep the FastAPI terminal open while testing the application. Stop the
server with `Ctrl+C`.

## Step 4: Useful Kubernetes commands

Use these commands to inspect the Jenkins installation:

``` bash
# List namespaces
kubectl get namespaces

# List Jenkins pods
kubectl get pods -n jenkins

# List Jenkins services
kubectl get svc -n jenkins

# Describe the Jenkins service
kubectl describe svc jenkins -n jenkins

# View Jenkins pod logs
kubectl logs -n jenkins jenkins-0

# Watch Jenkins pod status
kubectl get pods -n jenkins -w
```

## Troubleshooting

### `uvicorn: command not found`

Install the dependencies:

``` bash
python -m pip install -r requirements.txt
```

Then run Uvicorn as a Python module:

``` bash
python -m uvicorn app:app --reload
```

### Kubernetes API connection refused

Check that Docker Desktop is running and Kubernetes is enabled:

``` bash
kubectl cluster-info
kubectl get nodes
```

If the cluster is still starting, wait and retry. Also check that the
current kubectl context points to the intended cluster:

``` bash
kubectl config current-context
kubectl config get-contexts
```

### Jenkins dashboard does not open

Confirm that the Jenkins pod and service are available:

``` bash
kubectl get pods -n jenkins
kubectl get svc -n jenkins
```

Then restart port forwarding:

``` bash
kubectl port-forward svc/jenkins 8080:8080 -n jenkins
```

Browse to `http://localhost:8080` while the command is running.

### Port 8080 is already in use

Use another local port, for example:

``` bash
kubectl port-forward svc/jenkins 8081:8080 -n jenkins
```

Then open `http://localhost:8081`.

## Next steps: Build the complete CI/CD pipeline

After Jenkins and the FastAPI application are working, extend the lab in
this order:

1.  Push the FastAPI project to a GitHub repository.
2.  Add a `Jenkinsfile` with checkout, test, and build stages.
3.  Configure Jenkins credentials for the container registry.
4.  Build and push the FastAPI container image.
5.  Create Kubernetes Deployment and Service manifests.
6.  Configure Jenkins to deploy the new image to Kubernetes.
7.  Verify the deployed application and its health endpoint.

Do not store passwords, access tokens, or registry credentials directly
in the `Jenkinsfile` or source code. Use Jenkins credentials.

## Quick-start command summary

Run these commands from the appropriate directories:

``` bash
# From the repository root: install Jenkins
sh -x install-jenkins.sh

# Keep this running in a terminal: access Jenkins
kubectl port-forward svc/jenkins 8080:8080 -n jenkins

# In a second terminal: run FastAPI
cd fastapi-cicd-project
python -m pip install -r requirements.txt
python -m uvicorn app:app --reload
```

## Setup Docker Credentials

```bash
Log in to DockerHub.
Go to Account Settings.
Select Personal access tokens.
Generate a new token with appropriate read/write permissions.
Copy the token and save it in Jenkins.
   Manage Jenkins → Credentials → Global → Add Credentials
   
   eg:
      Kind: Username with password
            PASSWORD :Paste your DockerHub access token
            ID: dockerhub-credentials
   
   run sh -x export-kubeconfig.sh

   eg:
      Kind	Secret file
         File	Your kubeconfig file
         ID	kubeconfig-credentials
         Description	Kubernetes cluster access
```

### Jenkins Pipeline configuration tells it about GitHub

```bash
Open Jenkins via port forward command:
kubectl port-forward svc/jenkins 8080:8080 -n jenkins

 Definition → Pipeline script from SCM
 CI-CD_demo_fastapi - Display Name

```