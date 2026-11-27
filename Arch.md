## FastAPI CI/CD Pipeline

This project demonstrates an end-to-end CI/CD pipeline using Jenkins, Docker, DockerHub, and Kubernetes to automate the build, test, and deployment of a FastAPI application.

### CI/CD Pipeline Workflow

1. **Checkout**
   - Fetch source code from GitHub.
   - Checkout the latest code into the Jenkins workspace.

2. **Install Dependencies**
   - Install Python dependencies using `pip`.
   - Read required packages from `requirements.txt`.

3. **Test Application**
   - Validate the FastAPI application.
   - Verify that the application imports successfully.

4. **Build Docker Image**
   - Build a Docker image using the application's Dockerfile.
   - Tag the image with the Jenkins build number for versioning.

5. **Push Docker Image**
   - Authenticate with DockerHub using Jenkins Credentials.
   - Push the newly created Docker image to DockerHub.

6. **Deploy to Kubernetes**
   - Authenticate with the Kubernetes cluster using Jenkins Credentials.
   - Update the existing FastAPI Kubernetes Deployment with the new Docker image.
   - Monitor the deployment rollout.

7. **Verify Deployment**
   - Verify Kubernetes pod status.
   - Check Kubernetes services.
   - Confirm that the deployment rollout completed successfully.

### Pipeline Architecture

```text
        GitHub Repository
               |
               v
        Jenkins Pipeline
               |
               v
      Install Dependencies
               |
               v
       Test FastAPI App
               |
               v
       Build Docker Image
               |
               v
       Push to DockerHub
               |
               v
      Deploy to Kubernetes
               |
               v
       Verify Deployment
               |
               v
        Application Running
```

### Technologies Used

- **GitHub** – Source code management
- **Jenkins** – CI/CD automation
- **Python / FastAPI** – Application development
- **Docker** – Containerization
- **DockerHub** – Container image registry
- **Kubernetes** – Container orchestration

### Credentials Management

Jenkins Credentials Manager is used to securely maintain:

| Credential ID | Purpose |
|---|---|
| `dockerhub-credentials` | DockerHub authentication |
| `kubeconfig-credentials` | Kubernetes cluster access |

No passwords or access tokens are hardcoded in the Jenkinsfile.

### Expected Outcome

Whenever a new build is triggered, Jenkins automatically:

- Retrieves the latest application code.
- Installs dependencies and validates the application.
- Builds and publishes a versioned Docker image.
- Deploys the updated image to Kubernetes.
- Verifies the deployment status.

**Result:** An automated FastAPI CI/CD workflow from GitHub source code to Kubernetes deployment.