pipeline {
    agent {
        kubernetes {
            label 'maven'  // 确保Jenkins配置了名为'maven'的Kubernetes Pod模板
            yaml """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
              - name: jnlp
                image: jenkins/inbound-agent:4.11-1
                resources:
                  limits:
                    cpu: 500m
                    memory: 512Mi
              - name: maven  // 必须包含构建工具容器
                image: maven:3.8.6-jdk-11
                command: ['cat']
                tty: true
                resources:
                  limits:
                    cpu: 1000m
                    memory: 2Gi
            """
        }
    }

    parameters {
        gitParameter name: 'BRANCH_NAME',
                     branch: '',
                     branchFilter: '.*',
                     defaultValue: 'origin/master',
                     description: '请选择要发布的分支',
                     type: 'PT_BRANCH'

        string(name: 'TAG_NAME',
               defaultValue: 'snapshot',
               description: '标签名称，必须以 v 开头，例如：v1、v1.0.0')
    }

    environment {
        DOCKER_CREDENTIAL_ID = 'harbor-user-pass'
        GIT_REPO_URL = 'liulu.gitlab.com'
        GIT_CREDENTIAL_ID = 'gitlab-user-pass'
        GIT_ACCOUNT = 'root'
        REGISTRY = 'liulu.harbor.com'
        DOCKERHUB_NAMESPACE = 'devops'
        APP_NAME = 'k8s-cicd-demo'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm  // 必须添加代码检出步骤
            }
        }

        stage('Unit Test') {
            steps {
                container('maven') {  // 明确指定在maven容器中执行
                    sh 'mvn clean test'
                }
            }
        }

        stage('Build & Push') {
            steps {
                container('maven') {
                    sh 'mvn clean package -DskipTests'
                    script {
                        // 使用脚本块避免变量解析问题
                        def imageName = "${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:SNAPSHOT-${BUILD_NUMBER}"
                        sh "docker build -f Dockerfile -t ${imageName} ."

                        withCredentials([usernamePassword(
                            credentialsId: env.DOCKER_CREDENTIAL_ID,
                            usernameVariable: 'DOCKER_USERNAME',
                            passwordVariable: 'DOCKER_PASSWORD'
                        )]) {
                            sh """
                                echo "\$DOCKER_PASSWORD" | docker login ${REGISTRY} -u "\$DOCKER_USERNAME" --password-stdin
                                docker push ${imageName}
                            """
                        }
                    }
                }
            }
        }

        stage('Push Latest') {
            steps {
                container('maven') {
                    script {
                        sh """
                            docker tag ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:SNAPSHOT-${BUILD_NUMBER} \
                                ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:latest
                            docker push ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:latest
                        """
                    }
                }
            }
        }

        stage('Deploy to Dev') {
            steps {
                container('maven') {
                    sh """
                        sed -i.bak "s#REGISTRY#${REGISTRY}#g" deploy/cicd-demo-dev.yaml
                        sed -i.bak "s#DOCKERHUB_NAMESPACE#${DOCKERHUB_NAMESPACE}#g" deploy/cicd-demo-dev.yaml
                        sed -i.bak "s#APP_NAME#${APP_NAME}#g" deploy/cicd-demo-dev.yaml
                        sed -i.bak "s#BUILD_NUMBER#${BUILD_NUMBER}#g" deploy/cicd-demo-dev.yaml
                        kubectl apply -f deploy/cicd-demo-dev.yaml
                    """
                }
            }
        }

        stage('Push with Tag') {
            when {
                expression {
                    return params.TAG_NAME ==~ /v.*/
                }
            }
            steps {
                container('maven') {
                    withCredentials([usernamePassword(
                        credentialsId: env.GIT_CREDENTIAL_ID,
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_PASSWORD'
                    )]) {
                        sh """
                            git config --global user.email "liulu@gitlab.cn"
                            git config --global user.name "liulu"
                            git tag -a ${params.TAG_NAME} -m "${params.TAG_NAME}"
                            git push https://${GIT_USERNAME}:${GIT_PASSWORD}@${GIT_REPO_URL}/${GIT_ACCOUNT}/k8s-cicd-demo.git --tags --ipv4
                        """
                    }
                    sh """
                        docker tag ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:SNAPSHOT-${BUILD_NUMBER} \
                            ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:${params.TAG_NAME}
                        docker push ${REGISTRY}/${DOCKERHUB_NAMESPACE}/${APP_NAME}:${params.TAG_NAME}
                    """
                }
            }
        }

        stage('Deploy to Production') {
            when {
                expression {
                    return params.TAG_NAME ==~ /v.*/
                }
            }
            steps {
                container('maven') {
                    sh """
                        sed -i.bak "s#REGISTRY#${REGISTRY}#g" deploy/cicd-demo.yaml
                        sed -i.bak "s#DOCKERHUB_NAMESPACE#${DOCKERHUB_NAMESPACE}#g" deploy/cicd-demo.yaml
                        sed -i.bak "s#APP_NAME#${APP_NAME}#g" deploy/cicd-demo.yaml
                        sed -i.bak "s#TAG_NAME#${params.TAG_NAME}#g" deploy/cicd-demo.yaml
                        kubectl apply -f deploy/cicd-demo.yaml
                    """
                }
            }
        }
    }
}