pipeline {
    agent {
        kubernetes {
            label 'maven'
        }
    }

    parameters {
        gitParameter name: 'BRANCH_NAME',
                     branch: '',
                     branchFilter: '.*',
                     defaultValue: 'origin/master',
                     description: '请选择要发布的分支',
                     quickFilterEnabled: false,
                     selectedValue: 'NONE',
                     tagFilter: '*',
                     type: 'PT_BRANCH'
        string(name: 'TAG_NAME',
               defaultValue: 'snapshot',
               description: '标签名称，必须以 v 开头，例如：v1、v1.0.0')
    }

    environment {
        DOCKER_CREDENTIAL_ID = 'harbor-user-pass'
        GIT_REPO_URL = '192.168.241.102:28080'
        GIT_CREDENTIAL_ID = 'git-user-pass'
        GIT_ACCOUNT = 'root'
        REGISTRY = 'liulu.harbor.com'
        DOCKERHUB_NAMESPACE = 'devops' // 根据实际修改
        APP_NAME = 'k8s-cicd-demo'
    }

    stages {
        // 新增：清理 Maven 缓存
        stage('Clean Maven Cache') {
            steps {
                sh '''
                    echo "清理 plexus-compiler 缓存..."
                    rm -rf ~/.m2/repository/org/codehaus/plexus/plexus-compiler-*
                '''
            }
        }

        stage('unit 测试') {
            steps {
                sh 'mvn clean test'
            }
        }

        stage('build & push') {
            steps {
                // 强制更新依赖并构建
                sh 'mvn clean package -U'  // 添加 -U 参数

                sh 'docker build -f Dockerfile -t $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER .'
                withCredentials([usernamePassword(
                    passwordVariable: 'DOCKER_PASSWORD',
                    usernameVariable: 'DOCKER_USERNAME',
                    credentialsId: "$DOCKER_CREDENTIAL_ID"
                )]) {
                    sh 'echo "$DOCKER_PASSWORD" | docker login $REGISTRY -u "$DOCKER_USERNAME" --password-stdin'
                    sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER'
                }
            }
        }

        // 其他阶段保持不变...
        stage('push latest') {
            steps {
                sh 'docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest'
                sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:latest'
            }
        }

        stage('deploy to dev') {
            steps {
                input(id: 'deploy-to-dev', message: 'deploy to dev?')
                sh '''
                    sed -i'' "s#REGISTRY#$REGISTRY#" deploy/cicd-demo-dev.yaml
                    sed -i'' "s#DOCKERHUB_NAMESPACE#$DOCKERHUB_NAMESPACE#" deploy/cicd-demo-dev.yaml
                    sed -i'' "s#APP_NAME#$APP_NAME#" deploy/cicd-demo-dev.yaml
                    sed -i'' "s#BUILD_NUMBER#$BUILD_NUMBER#" deploy/cicd-demo-dev.yaml
                    kubectl apply -f deploy/cicd-demo-dev.yaml
                '''
            }
        }

        stage('push with tag') {
            steps {
                input(id: 'release-image-with-tag', message: 'release image with tag?')
                withCredentials([usernamePassword(
                    credentialsId: "$GIT_CREDENTIAL_ID",
                    passwordVariable: 'GIT_PASSWORD',
                    usernameVariable: 'GIT_USERNAME'
                )]) {
                    sh 'git config --global user.email "liulu@git.cn" '
                    sh 'git config --global user.name "liulu" '
                    sh 'git tag -a $TAG_NAME -m "$TAG_NAME" '
                    sh 'git push http://$GIT_USERNAME:$GIT_PASSWORD@$GIT_REPO_URL/$GIT_ACCOUNT/k8s-cicd-demo.git --tags --ipv4'
                }
                sh 'docker tag $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:SNAPSHOT-$BUILD_NUMBER $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$TAG_NAME'
                sh 'docker push $REGISTRY/$DOCKERHUB_NAMESPACE/$APP_NAME:$TAG_NAME'
            }
        }

        stage('deploy to production') {
            steps {
                input(id: 'deploy-to-production', message: 'deploy to production?')
                sh '''
                    sed -i'' "s#REGISTRY#$REGISTRY#" deploy/cicd-demo.yaml
                    sed -i'' "s#DOCKERHUB_NAMESPACE#$DOCKERHUB_NAMESPACE#" deploy/cicd-demo.yaml
                    sed -i'' "s#APP_NAME#$APP_NAME#" deploy/cicd-demo.yaml
                    sed -i'' "s#TAG_NAME#$TAG_NAME#" deploy/cicd-demo.yaml
                    kubectl apply -f deploy/cicd-demo.yaml
                '''
            }
        }
    }
}