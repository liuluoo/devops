pipeline {
    agent {
        kubernetes {
            label 'maven'
        }
    }

    parameters {
        gitParameter name: 'BRANCH_NAME', branch: '', branchFilter: '.*', defaultValue: 'origin/master', description: '请选择要发布的分支', quickFilterEnabled: false, selectedValue: 'NONE', tagFilter: '*', type: 'PT_BRANCH'
        string(name: 'TAG_NAME', defaultValue: 'snapshot', description: '标签名称，必须以 v 开头，例如：v1、v1.0.0')
    }

    environment {
        DOCKER_CREDENTIAL_ID = 'harbor-user-pass'
        GIT_REPO_URL = 'liulu.gitlab.com'
        GIT_CREDENTIAL_ID = 'git-user-pass'
        GIT_ACCOUNT = 'root'
        REGISTRY = 'liulu.harbor.com'
        DOCKERHUB_NAMESPACE = 'devops'
        APP_NAME = 'k8s-cicd-demo'
        // 定义命名空间变量
        DEV_NAMESPACE = 'devops-dev'
        PROD_NAMESPACE = 'devops-production'
        KUBECONFIG_CREDENTIAL_ID  = 'k8s-cluster-config'
    }

    stages {
        stage('unit test') {
            steps {
                sh 'mvn clean test'
            }
        }

        stage('build & push') {
            steps {
                sh 'mvn clean package -DskipTests'
                sh 'docker build -f Dockerfile -t $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER .'
                withCredentials([usernamePassword(passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME', credentialsId: "$DOCKER_CREDENTIAL_ID",)]) {
                    sh 'echo "$DOCKER_PASSWORD" | docker login $REGISTRY -u "$DOCKER_USERNAME" --password-stdin'
                    sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER'
                }
            }
        }

        stage('push latest') {
            steps {
                sh 'docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest'
                sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest'
            }
        }

        stage('deploy to dev') {
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: env.KUBECONFIG_CREDENTIAL_ID, variable: 'KUBECONFIG_FILE')]) {
                        sh '''
                            # 合并kubeconfig
                            mkdir -p ~/.kube
                            cp ${KUBECONFIG_FILE} ~/.kube/config
                            chmod 600 ~/.kube/config

                            # 执行部署命令
                            kubectl create namespace $DEV_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
                            kubectl apply -f deploy/deploy-processed.yaml -n $DEV_NAMESPACE
                        '''
                    }
                }
            }
        }

        stage('push with tag') {
            when {
                expression { return params.TAG_NAME =~ /v.*/ }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: "$GIT_CREDENTIAL_ID", passwordVariable: 'GIT_PASSWORD', usernameVariable: 'GIT_USERNAME')]) {
                    sh 'git config --global user.email "liulu@gitlab.cn" '
                    sh 'git config --global user.name "liulu" '
                    sh 'git tag -a $TAG_NAME -m "$TAG_NAME" '
                    sh 'git push http://$GIT_USERNAME:$GIT_PASSWORD@$GIT_REPO_URL/$GIT_ACCOUNT/k8s-cicd-demo.git --tags --ipv4'
                }
                sh 'docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$TAG_NAME'
                sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$TAG_NAME'
            }
        }

        stage('deploy to production') {
            when {
                expression { return params.TAG_NAME =~ /v.*/ }
            }
            steps {
                sh '''
                    # 创建生产命名空间（如果不存在）
                    kubectl create namespace $PROD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

                    # 部署应用到生产环境
                    sed -i'' "s#REGISTRY#$REGISTRY#" deploy/cicd-demo.yaml
                    sed -i'' "s#DOCKERHUB_NAMESPACE#$DOCKERHUB_NAMESPACE#" deploy/cicd-demo.yaml
                    sed -i'' "s#APP_NAME#$APP_NAME#" deploy/cicd-demo.yaml
                    sed -i'' "s#TAG_NAME#$TAG_NAME#" deploy/cicd-demo.yaml
                    kubectl apply -f deploy/cicd-demo.yaml -n $PROD_NAMESPACE

                    # 验证部署状态
                    kubectl rollout status deployment/$APP_NAME -n $PROD_NAMESPACE --timeout=300s
                '''
            }
        }
    }
}