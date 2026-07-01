# EKS Hybrid Compute — Fargate + Nodegroup, Stateful Helm & Autoscaling

> **FR** — Cluster Amazon EKS à compute hybride : une application Java Spring Boot tourne sur un **profil Fargate** dédié, tandis que MySQL (réplication) et phpMyAdmin tournent sur un **nodegroup EC2** avec stockage persistant EBS. Le **Cluster Autoscaler** ajuste le nodegroup via IRSA, et une pipeline Jenkins (Gradle, ECR) construit et déploie l'application.
>
> **EN** — Amazon EKS cluster with hybrid compute: a Java Spring Boot application runs on a dedicated **Fargate profile**, while MySQL (replication) and phpMyAdmin run on an **EC2 managed nodegroup** with persistent EBS storage. **Cluster Autoscaler** scales the nodegroup via IRSA, and a Jenkins pipeline (Gradle, ECR) builds and deploys the application.

---

## Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS-326CE5?logo=kubernetes)
![AWS Fargate](https://img.shields.io/badge/AWS-Fargate-FF9900?logo=amazonaws)
![Helm](https://img.shields.io/badge/Helm-charts-0F1689?logo=helm)
![MySQL](https://img.shields.io/badge/MySQL-replication-4479A1?logo=mysql)
![Jenkins](https://img.shields.io/badge/Jenkins-CI%2FCD-red?logo=jenkins)
![Gradle](https://img.shields.io/badge/Gradle-build-02303A?logo=gradle)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3-6DB33F?logo=springboot)
![Docker](https://img.shields.io/badge/Docker-ECR-2496ED?logo=docker)
![Cluster Autoscaler](https://img.shields.io/badge/Cluster%20Autoscaler-IRSA-orange?logo=amazonaws)

---

## What this demonstrates

- **Hybrid compute allocation** — stateless application workload on Fargate (`my-app` namespace) isolated from stateful infrastructure (MySQL, phpMyAdmin) on a managed EC2 nodegroup (`default` namespace), with cross-namespace service discovery via Kubernetes DNS.
- **Stateful workloads with Helm** — MySQL deployed in `replication` mode (primary/secondary) with EBS-backed persistence, provisioned dynamically via the **AWS EBS CSI driver** (IRSA-authenticated, no static credentials in-cluster).
- **Cluster Autoscaler via IRSA** — the nodegroup scales automatically based on pending pod demand, authenticated through a scoped IAM role (OIDC federation), not long-lived keys.
- **CI/CD with Jenkins** — Gradle build, Docker image pushed to Amazon ECR, Kubernetes manifests templated with `envsubst` and applied via `kubectl`.

---

## Architecture

```
                        ┌─────────────────────────────┐
                        │        Amazon EKS            │
                        │                               │
   Jenkins Pipeline     │  ┌─────────────────────────┐  │
   ├─ 1. Build (Gradle) │  │  Fargate profile         │  │
   ├─ 2. Docker build   │──▶  namespace: my-app       │  │
   ├─ 3. Push → ECR     │  │  └── java-app Deployment │  │
   └─ 4. kubectl apply  │  └───────────┬─────────────┘  │
                        │              │ DNS (FQDN,      │
                        │              │ cross-namespace) │
                        │  ┌───────────▼─────────────┐  │
                        │  │  EC2 Managed Nodegroup   │  │
                        │  │  namespace: default      │  │
                        │  │  ├── mysqldb (Helm,      │  │
                        │  │  │   replication + EBS)  │  │
                        │  │  └── phpMyAdmin          │  │
                        │  │  namespace: kube-system   │  │
                        │  │  ├── EBS CSI driver (IRSA)│  │
                        │  │  └── Cluster Autoscaler   │  │
                        │  │      (IRSA)               │  │
                        │  └─────────────────────────┘  │
                        └─────────────────────────────┘
```

---

## Jenkins Prerequisites

| Credential ID | Type | Usage |
|---|---|---|
| `ecr-credentials` | Username/Password | Docker login to Amazon ECR |
| `jenkins_aws_access_key_id` | Secret text | AWS IAM auth for EKS (`eks update-kubeconfig`) |
| `jenkins_aws_secret_access_key` | Secret text | AWS IAM auth for EKS |

| Tool | Provisioning |
|---|---|
| Gradle | Jenkins Gradle plugin (`tools { gradle 'gradle' }`), auto-installed |
| kubectl / AWS CLI | Installed on the Jenkins agent |

---

## Project Structure

```
.
├── Jenkinsfile                          # CI/CD pipeline (Gradle build, ECR push, kubectl deploy)
├── Dockerfile                           # Java app image (Eclipse Temurin 21)
├── build.gradle / settings.gradle       # Gradle project (Spring Boot 3)
├── manifests/
│   ├── java-app.yaml                    # Deployment + Service (Fargate, namespace my-app)
│   ├── java-app-configMap.yaml          # DB connection config (cross-namespace FQDN)
│   ├── java-app-secret.yaml             # DB credentials
│   ├── phpmyadmin.yaml                  # phpMyAdmin Deployment + Service
│   └── ingress.yaml                     # Ingress routing
├── mysql/values.yaml                    # Bitnami MySQL Helm values (replication + EBS)
├── charts/app/                          # Reusable Helm chart (used by helmfile)
├── values/                              # Helmfile values per release
├── helmfile.yaml                        # Helmfile release definitions
└── src/                                 # Java Spring Boot application source
```

---

## Key design decisions

- **Why split compute between Fargate and a nodegroup?** Fargate removes node management for the stateless app tier, while stateful services (databases) stay on EC2-backed nodes where persistent EBS volumes and node-level tuning are supported.
- **Why cross-namespace FQDN for the database connection?** Kubernetes namespaces are a logical boundary, not a network one — pods across namespaces share the same cluster network, but short-form DNS only resolves within the same namespace. The app therefore targets the MySQL service by its full `service.namespace.svc.cluster.local` name.
- **Why IRSA for the EBS CSI driver and Cluster Autoscaler?** Both need AWS API access (EC2 volume operations, Auto Scaling Group operations) without embedding long-lived credentials in the cluster — IAM Roles for Service Accounts exchange short-lived, automatically rotated tokens for temporary AWS credentials.
