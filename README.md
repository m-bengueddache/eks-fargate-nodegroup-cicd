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

## FR — Description

### Partie 1 — Compute hybride : Fargate + Nodegroup

Profil Fargate dédié (namespace `my-app`) pour l'application Spring Boot, isolé du nodegroup EC2 managé (namespace `default`) qui héberge MySQL et phpMyAdmin.

Un namespace Kubernetes est une frontière logique (RBAC, quotas), pas une frontière réseau — tous les pods du cluster partagent le même réseau VPC, que ce soit sur Fargate ou sur EC2. Seule la résolution DNS courte est limitée au namespace courant : l'application cible donc le service MySQL par son FQDN complet (`service.namespace.svc.cluster.local`) plutôt que par son nom court, puisqu'ils sont dans des namespaces différents.

### Partie 2 — Déploiement stateful avec Helm

MySQL déployé en mode `replication` (primaire/secondaire) via le chart Bitnami, avec persistance EBS provisionnée dynamiquement par l'**EBS CSI driver** (authentifié via IRSA, sans credentials statiques dans le cluster). phpMyAdmin déployé en complément pour l'administration de la base.

### Partie 3 — Cluster Autoscaler (IRSA)

Le nodegroup EC2 s'ajuste automatiquement à la demande de pods en attente, via un rôle IAM restreint (fédération OIDC) plutôt que des clés statiques. Les Service Accounts Kubernetes ne sont pas des entités IAM : IRSA fait le pont en échangeant un token JWT signé par l'émetteur OIDC du cluster contre des credentials AWS temporaires, scopés au strict nécessaire (`autoscaling:*`, `ec2:Describe*`).

### Partie 4 — Pipeline CI/CD Jenkins

Build Gradle, image Docker poussée vers Amazon ECR, manifests Kubernetes templatés avec `envsubst` puis appliqués via `kubectl`. Le tag d'image est généré dynamiquement (numéro de build Jenkins), jamais hardcodé dans les manifests déployés.

## EN — Description

### Part 1 — Hybrid compute: Fargate + Nodegroup

Dedicated Fargate profile (`my-app` namespace) for the Spring Boot application, isolated from the managed EC2 nodegroup (`default` namespace) hosting MySQL and phpMyAdmin.

A Kubernetes namespace is a logical boundary (RBAC, quotas), not a network one — all pods in the cluster share the same VPC network, whether on Fargate or EC2. Only short-form DNS resolution is limited to the current namespace: the application therefore targets the MySQL service by its full FQDN (`service.namespace.svc.cluster.local`) rather than its short name, since they live in different namespaces.

### Part 2 — Stateful deployment with Helm

MySQL deployed in `replication` mode (primary/secondary) via the Bitnami chart, with EBS persistence dynamically provisioned by the **EBS CSI driver** (IRSA-authenticated, no static credentials in-cluster). phpMyAdmin deployed alongside for database administration.

### Part 3 — Cluster Autoscaler (IRSA)

The EC2 nodegroup scales automatically based on pending pod demand, through a scoped IAM role (OIDC federation) rather than static keys. Kubernetes Service Accounts aren't IAM entities — IRSA bridges that gap by exchanging a JWT token signed by the cluster's OIDC issuer for temporary AWS credentials, scoped to the bare minimum (`autoscaling:*`, `ec2:Describe*`).

### Part 4 — Jenkins CI/CD pipeline

Gradle build, Docker image pushed to Amazon ECR, Kubernetes manifests templated with `envsubst` and applied via `kubectl`. The image tag is generated dynamically (Jenkins build number), never hardcoded in the deployed manifests.

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
