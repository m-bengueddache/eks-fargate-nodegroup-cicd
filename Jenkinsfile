#!/usr/bin/env groovy

pipeline {
    agent any
    tools {
        gradle 'gradle'
    }
    environment {
        DOCKER_REPO_SERVER = '123456789012.dkr.ecr.eu-west-3.amazonaws.com'
        DOCKER_REPO = "${DOCKER_REPO_SERVER}/java-app"
    }
    stages {
        stage('increment version') {
            steps {
                script {
                    echo 'setting build version...'
                    env.IMAGE_NAME = "${BUILD_NUMBER}"
                }
            }
        }
        stage('build app') {
            steps {
                script {
                    echo 'building the application...'
                    sh 'gradle clean build'
                }
            }
        }
        stage('build image') {
            steps {
                script {
                    echo "building the docker image..."
                    withCredentials([usernamePassword(credentialsId: 'ecr-credentials', passwordVariable: 'PASS', usernameVariable: 'USER')]){
                        sh "docker build -t ${DOCKER_REPO}:${IMAGE_NAME} ."
                        sh 'echo $PASS | docker login -u $USER --password-stdin ${DOCKER_REPO_SERVER}'
                        sh "docker push ${DOCKER_REPO}:${IMAGE_NAME}"
                    }
                }
            }
        }
        stage('deploy') {
            environment {
                AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
                AWS_SECRET_ACCESS_KEY = credentials('jenkins_aws_secret_access_key')
                KUBECONFIG = '/var/jenkins_home/.kube/config-aws'
                APP_NAME = 'java-app'
                CLUSTER_NAME = 'demo-cluster'
                REGION_NAME = 'eu-west-3'
            }
            steps {
                script {
		            echo 'refreshing kubeconfig...'
                    sh 'aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION_NAME --kubeconfig $KUBECONFIG'

                    echo 'deploying docker image...'
                    sh 'kubectl create namespace my-app --dry-run=client -o yaml | kubectl apply -f -'

                    sh 'kubectl apply -f manifests/java-app-configMap.yaml -n my-app'
                    sh 'kubectl apply -f manifests/java-app-secret.yaml -n my-app'
                    sh 'envsubst < manifests/java-app.yaml | kubectl apply -f -'
                }
            }
        }
    }
}