pipeline {
    agent {
        kubernetes {
            label 'maven'
            // 增加资源限制防止Agent崩溃
            yaml '''
                spec:
                    containers:
                    - name: jnlp
                      resources:
                          limits:
                              cpu: 1
                              memory: 2Gi
                    - name: kubectl  # 添加kubectl工具容器
                      image: bitnami/kubectl:latest
                      command: ["sleep", "infinity"]
            '''
        }
    }

    parameters {
        gitParameter name: 'BRANCH_NAME',
                     defaultValue: 'origin/master',
                     description: '请选择要发布的分支'
        string(name: 'TAG_NAME',
               defaultValue: 'snapshot',
               description: '标签名称，必须以 v 开头')
    }

    environment {
        DOCKER_CREDENTIAL_ID = 'harbor-user-pass'
        REGISTRY = 'liulu.harbor.com'
        DOCKERHUB_NAMESPACE = 'devops'
        APP_NAME = 'k8s-cicd-demo'
        // 新增K8s命名空间变量
        DEV_NAMESPACE = 'dev-production'
        PROD_NAMESPACE = 'devops-dev'
    }

    stages {
        stage('Clean Maven Cache') {
            steps {
                sh 'rm -rf ~/.m2/repository/org/codehaus/plexus/plexus-compiler-*'
            }
        }

        stage('Unit Test') {
            steps {
                sh 'mvn clean test'
            }
        }

        stage('Build & Push Snapshot') {
            steps {
                sh 'mvn clean package -U'
                sh 'docker build -f Dockerfile -t $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER .'
                withCredentials([usernamePassword(
                    credentialsId: "$DOCKER_CREDENTIAL_ID",
                    passwordVariable: 'DOCKER_PASSWORD',
                    usernameVariable: 'DOCKER_USERNAME'
                )]) {
                    sh '''
                        echo "$DOCKER_PASSWORD" | docker login $REGISTRY -u "$DOCKER_USERNAME" --password-stdin
                        docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER
                    '''
                }
            }
        }

        stage('Push Latest') {
            steps {
                sh '''
                    docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest
                    docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest
                '''
            }
        }

        stage('Deploy to Dev') {
            steps {
                script {
                    // 增加超时和手动确认
                    timeout(time: 10, unit: 'MINUTES') {
                        input(
                            id: 'DeployDev',
                            message: '确认部署到开发环境？',
                            parameters: [
                                choice(
                                    name: 'ACTION',
                                    choices: 'Proceed\nAbort',
                                    description: '选择操作'
                                )
                            ]
                        )
                    }

                    // 仅在确认后执行部署
                    container('kubectl') {  // 使用包含kubectl的容器
                        sh '''
                            # 调试：打印关键变量
                            echo "===== 部署配置 ====="
                            echo "镜像: $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER"
                            echo "命名空间: $DEV_NAMESPACE"

                            # 创建命名空间（如果不存在）
                            kubectl create namespace $DEV_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

                            # 使用envsubst实现更安全的变量替换
                            envsubst < deploy/cicd-demo-dev.yaml > deploy/cicd-demo-dev-processed.yaml
                            echo "===== 生成的YAML ====="
                            cat deploy/cicd-demo-dev-processed.yaml

                            # 部署并检查状态
                            kubectl apply -f deploy/cicd-demo-dev-processed.yaml
                            kubectl rollout status deployment/$APP_NAME -n $DEV_NAMESPACE --timeout=300s
                        '''
                    }
                }
            }
        }

        stage('Push with Tag') {
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        input(
                            id: 'ReleaseTag',
                            message: '确认发布正式版本？',
                            parameters: [
                                string(
                                    name: 'CONFIRM_TAG',
                                    defaultValue: "$TAG_NAME",
                                    description: '请输入版本标签'
                                )
                            ]
                        )
                    }

                    sh '''
                        docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$CONFIRM_TAG
                        docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$CONFIRM_TAG
                    '''
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        input(
                            id: 'DeployProd',
                            message: '确认部署到生产环境？',
                            parameters: [
                                choice(
                                    name: 'ACTION',
                                    choices: 'Proceed\nAbort',
                                    description: '选择操作'
                                )
                            ]
                        )
                    }

                    container('kubectl') {
                        sh '''
                            kubectl create namespace $PROD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
                            envsubst < deploy/cicd-demo.yaml > deploy/cicd-demo-processed.yaml
                            kubectl apply -f deploy/cicd-demo-processed.yaml
                            kubectl rollout status deployment/$APP_NAME -n $PROD_NAMESPACE --timeout=300s
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            // 清理工作空间
            cleanWs()
        }
        failure {
            // 失败时发送通知
            emailext body: '构建失败: ${BUILD_URL}',
                    subject: 'Jenkins构建失败: ${JOB_NAME}',
                    to: 'devops@example.com'
        }
    }
}