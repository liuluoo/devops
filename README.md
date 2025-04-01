

# Devops流水线项目实践

本次配置和代码都在[github](https://github.com/kehaha-5/k8s_demo)上

流程图如下：

![image](https://github.com/user-attachments/assets/5990bda1-3ae4-42ab-87d0-43affdf5b605)


环境如下：

| 主机名     |          IP地址 |          系统版本           |
| :--------- | --------------: | :-------------------------: |
| controller | 192.168.241.101 | Rocky Linux 9.5 (Blue Onyx) |
| node01     | 192.168.241.102 | Rocky Linux 9.5 (Blue Onyx) |
| node02     | 192.168.241.103 | Rocky Linux 9.5 (Blue Onyx) |

## 一、NFS网络存储服务器搭建

首先部署NFS网络存储服务器，这里配置了Node02为nfs节点

```
[root@node02 kubernetes]# dnf install nfs-utils -y#下载nfs网络文件管理工具
[root@node02 kubernetes]# systemctl start nfs-server
[root@node02 kubernetes]# systemctl enable nfs-server
Created symlink /etc/systemd/system/multi-user.target.wants/nfs-server.service → /usr/lib/systemd/system/nfs-server.service.
[root@node02 nfs]# mkdir -p /data/nfs
[root@node02 nfs]# cd /data/nfs
[root@node02 nfs]# mkdir rw
[root@node02 nfs]# mkdir ro
```

修改etc/exports中的文件权限，rw可读写，ro只读

![image](https://github.com/user-attachments/assets/3b2bb84b-c2d9-4105-8845-3a1669dc52b6)


以下为部署的yaml文件，先给nfs创建一个namespace

```
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: kube-nfs-storage
  name: kube-nfs-storage
```

这里我选择用storageclass的**Provisioner** 去动态创建和管理存储卷，后期用户只需要定义存储空间规则pvc就可以了，由provisioner去动态地生成pc

```
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
provisioner: fuseim.pri/ifs
parameters:
  archiveOnDelete: "false"
```

因为我们的storageclass要操作不同的namespace，这里我即配置了**ClusterRole**：用于授权 Provisioner 管理集群级资源（PV、StorageClasses）和跨命名空间资源（所有 PVC、Endpoints），又配置了**Role**：用于授权 Provisioner 在特定命名空间（`kube-nfs-storage`）内操作 Endpoints

```
rbac配置如下：
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
- kind: ServiceAccount
  name: nfs-client-provisioner
  namespace: kube-nfs-storage
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
rules:
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
subjects:
- kind: ServiceAccount
  name: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: kube-nfs-storage
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io

```

```
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
- kind: ServiceAccount
  name: nfs-client-provisioner
  namespace: kube-nfs-storage
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
rules:
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
subjects:
- kind: ServiceAccount
  name: nfs-client-provisioner
  namespace: kube-nfs-storage
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io

```

以下为deployment文件，这里指定了 nfs-client-provisioner的数据持久化挂载的地址为我刚刚在/date目录下创建的rw文件夹，镜像下载地址更换为我本地镜像（已提前通过官网下载导入），添加了PROVISIONER的环境变量

```
deployment配置如下：
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: kube-nfs-storage
---
kind: Deployment
apiVersion: apps/v1
metadata:
  namespace: kube-nfs-storage
  name: nfs-client-provisioner
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccount: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: fuseim.pri/ifs
            - name: NFS_SERVER
              value: 192.168.241.103
            - name: NFS_PATH
              value: /data/nfs/rw
      volumes:
        - name: nfs-client-root
          nfs:
            server: 192.168.241.103
            path: /data/nfs/rw

```

## 二、harbor镜像仓库搭建

nfs部署完成接下来，部署`harbor`作为私有镜像仓库，便于后期上传构建的镜像。这里harbor的安装我采用的helm方式，同时因为Jenkins、GitLab 等工具可能强制要求HTTPS，另外为了模拟实际生产环境，增强访问控制，所以我用刚才的中间ca证书给harbor服务签了一个终端证书,这先写了一个secret去保存harbor的TLS证书

```
secret配置如下：
apiVersion: v1
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1J.......
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1J.......
kind: Secret
metadata:
  creationTimestamp: "2025-03-20T15:49:21Z"
  name: harbor-tls
  namespace: devops
  resourceVersion: "40087"
  uid: f9ccc9c1-eb6a-4777-b5af-f5331398a62b
type: kubernetes.io/tls
```

service的类型为clusterip，然后通过ingress方式去暴露harbor服务，同时添加刚才的TLS证书的secret，把数据持久化到我们刚才搭建的nfs服务器上，由managed-nfs-storage动态分配pc

```
  value.yaml配置如下：
  type: ingress
  tls:
   disabled and "expose.type" is "ingress"
    certSource: secret
    auto:
      commonName: ""
    secret:
      secretName: "harbor-tls"
  ingress:
    hosts:
      core: liulu.harbor.com
    controller: default
    ## Allow .Capabilities.KubeVersion.Version to be overridden while creating ingress
    kubeVersionOverride: ""
    className: ""
    annotations:
      # note different ingress controllers may require a different ssl-redirect annotation
      # for Envoy, use ingress.kubernetes.io/force-ssl-redirect: "true" and remove the nginx lines below
      ingress.kubernetes.io/ssl-redirect: "true"
      ingress.kubernetes.io/proxy-body-size: "
 ........................................................................................
 
     persistentVolumeClaim:
    registry:
      existingClaim: ""
      storageClass: "managed-nfs-storage"
      subPath: ""
      accessMode: ReadWriteOnce
      size: 5Gi
      annotations: {}
    jobservice:
      jobLog:
        existingClaim: ""
        storageClass: "managed-nfs-storage"
        subPath: ""
        accessMode: ReadWriteOnce
        size: 1Gi
        annotations: {}
    database:
      existingClaim: ""
      storageClass: "managed-nfs-storage"
      subPath: ""
      accessMode: ReadWriteOnce
      size: 1Gi
.........................................................................................
```

helm安装完毕，服务器去信任证书链的ca根证书，添加并刷新本地dns解析，就可以通过域名访问我的harbor了，dockerlogin之前也需要把harbor的服务器证书提前拷贝到/etc/docker/certs.d/目录下，效果如下

![image](https://github.com/user-attachments/assets/e32c7ed8-b16a-46fc-a772-6706083664c3)


## 三、gitlab代码仓库搭建

接下来部署gitlab，因为代码仓库需要高IOPS和低延迟的存储，而数据库则需要稳定的性能和高可靠性，所以这里基于集群外部部署，把数据持久化到本地服务器上，我选择controller节点作为本地代码仓库，通过我yum仓库里的gitlab源来安装，以下为我在gitlab.rb中修改的参数，因为笔记本资源有限，所以改小了并发数和缓存容量

```
gitlab_rails['time_zone'] = 'Asia/Shanghai'
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 8
postgresql['shared_buffers'] = "128MB"
postgresql['max_worker_processes'] = 4
prometheus_monitoring['enable'] = false
```

![image](https://github.com/user-attachments/assets/9b4d5a20-7adb-4ca4-8e78-4b9ce95c9697)


这里用了gitlab自带的nginx做反向代理，证书用我们提前签好的证书链和私钥，配置在对应文件夹

## 四、Jenkins搭建

然后是部署jenkins，因为我的测试代码是java项目，要用到maven构建，这里选择用dockerfile去打一个带maven环境的jenkins镜像便于后期部署，同时还要写一个configmap去给maven依赖指定拉取地址

```
config配置代码如下
apiVersion: v1
kind: ConfigMap
metadata:
  name: mvn-settings
  namespace: devops
  labels:
    app: jenkins-server
data:
  settings.xml: |-
    <?xml version="1.0" encoding="UTF-8"?>
    <settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd"> #后期可以根据需求加一个nexus本地依赖仓库

Dockerfile配置如下：
FROM jenkins/jenkins:2.430-jdk21
ADD ./apache-maven-3.9.0-bin.tar.gz /usr/local/

USER root
WORKDIR /usr/local/

ENV MAVEN_HOME=/usr/local/apache-maven-3.9.7
ENV PATH=$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH

RUN echo "jenkins ALL=NOPASSWD: ALL" >> /etc/sudoers
USER jenkins
```

dockerbuild完push到我们本地的harbor仓库

![image](https://github.com/user-attachments/assets/d5f543e7-f428-4de2-bb72-dcfa16503e4d)



这里jenkins我参考了官网的安装步骤进行部署[Kubernetes](https://www.jenkins.io/doc/book/installing/kubernetes/)，根据需求来更改配置，写了service的角色和rolebinding，因为jenkins要操作不同的ns，所以给他clusterrole的角色

```
service+rolebinding+clusterrole配置如下：
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-admin
rules:
  - apiGroups: [""]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-admin
  namespace: devops
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-admin
subjects:
- kind: ServiceAccount
  name: jenkins-admin
  namespace: devops
```

然后是Jenkins的pvc的要求，交给managed-nfs-storage去分配pv

```
pvc配置如下：
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: devops
spec:
  storageClassName: managed-nfs-storage
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi#生产环境会大很多，这里只是演示项目
```

等下创建deployment要用到我们刚刚打好的jenkins镜像，必须要提前写一个secret保存harbor的账号密码以便拉取，此外由于jenkins在流水线中要构建和上传镜像，操作k8s集群，我们还需要提前把服务器的docker的调用接口文件docker.sock和kubectl映射给jenkins使用，把我们的根证书也映射给容器，便于信任其他服务

```
secret生成：
[root@controller opt]# kubectl create secret docker-registry harbor-secret --docker-username=admin --docker-password=harbor --docker-server=liulu.harbor.com -n devops
secret/harbor-secret created
```

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: devops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-server
  template:
    metadata:
      labels:
        app: jenkins-server
    spec:
      serviceAccountName: jenkins-admin
      imagePullSecrets: 
        - name: harbor-secret # harbor 访问 secret
      containers:
        - name: jenkins
          image: liulu.harbor.com/devops/myjenkins-jdk21-maven3.9.7:v1
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
            runAsUser: 0 # 使用 root 用户运行容器
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
            requests:
              memory: "500Mi"
              cpu: "500m"
          ports:
            - name: httpport
              containerPort: 8080
            - name: jnlpport
              containerPort: 50000
          livenessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          volumeMounts:
            - name: jenkins-data
              mountPath: /var/jenkins_home
            - name: docker
              mountPath: /run/docker.sock #映射主机的docker接口给jenkins
            - name: docker-home
              mountPath: /usr/bin/docker
            - name: mvn-setting
              mountPath: /usr/local/apache-maven-3.9.7/conf/settings.xml
              subPath: settings.xml
            - name: daemon
              mountPath: /etc/docker/daemon.json
              subPath: daemon.json
            - name: kubectl
              mountPath: /usr/bin/kubectl
            - name: ca-cert-volume
              mountPath: /usr/local/share/ca-certificates/
              readOnly: true
      volumes:
        - name: kubectl
          hostPath:
            path: /usr/bin/kubectl
        - name: jenkins-data
          persistentVolumeClaim:
              claimName: jenkins-pvc
        - name: docker
          hostPath:
            path: /run/docker.sock # 将主机的 docker 映射到容器中
        - name: docker-home
          hostPath:
            path: /usr/bin/docker
        - name: mvn-setting
          configMap:
            name: mvn-settings
            items:
            - key: settings.xml
              path: settings.xml
        - name: daemon
          hostPath: 
            path: /etc/docker/
        - name: ca-cert-volume #映射我们的ca根证书
          configMap:
            name: ca-cert-configmap

```

jenkins对外暴露方式依然是ingress，基于https协议访问，也是提前签了一个终端证书给它，创建一个secret把它tls握手时需要的证书给挂上去，另外根据官方文档，重写了ingress代理的重定向配置

```
apiVersion: v1
kind: Service
metadata:
  name: jenkins-service
  namespace: devops
  annotations:
    prometheus.io/scrape: 'true'
    prometheus.io/path: /
    prometheus.io/port: '8080'
spec:
  selector:
    app: jenkins-server
  type: ClusterIP  # 内部集群访问
  ports:
    - port: 8080
      targetPort: 8080
---
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-ingress
  namespace: devops
  annotations:
    # 后端协议（保持 HTTP）
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"

    # 上传文件大小限制
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"

    # 重定向配置
    nginx.ingress.kubernetes.io/proxy-redirect-from: "http://jenkins-service.devops.svc.cluster.local:8080/"
    nginx.ingress.kubernetes.io/proxy-redirect-to: "https://$host/"

   
    nginx.ingress.kubernetes.io/proxy-set-headers: |
      X-Forwarded-Proto $scheme
      X-Forwarded-Host $host
      X-Forwarded-Port $server_port

    # HTTPS 强制跳转
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

    # 路径重写
    # nginx.ingress.kubernetes.io/rewrite-target: /

spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - liulu.jenkins.com
    secretName: jenkins-tls  # 我们之前创建的证书secret
  rules:
  - host: liulu.jenkins.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jenkins-service
            port:
              number: 8080

```

这里对coredns加了本地域名解析，便于我们的jenkins可以正确解析到其他服务

![image](https://github.com/user-attachments/assets/09083277-f6b6-45bb-a248-c6c9b65c76f7)




通过容器日志查看jenkins初始密码，安装插件，创建流水线任务，添加一个kubernetes的云给到jenkins，把harbor和gitlab的凭据也写进来，gitlab那边配置webhook，复制jenkins的token给到webhook，测试push事件是否能够触发

![image](https://github.com/user-attachments/assets/9f3a45fd-0fe3-4278-9e55-1a0472360d96)


![image](https://github.com/user-attachments/assets/93b97087-321f-4342-bbc8-3538a6d6eb2f)


![image](https://github.com/user-attachments/assets/91b15215-5bb5-4e8a-9a6e-275d3d3f44f1)


## 五、项目构建

现在所有中间件基本齐活了，接下来写一个pipeline去自动化部署就可以了

```
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
        GIT_CREDENTIAL_ID = 'gitlab-user-pass'
        GIT_ACCOUNT = 'root'
        REGISTRY = 'liulu.harbor.com'
        DOCKERHUB_NAMESPACE = 'devops'
        APP_NAME = 'k8s-cicd-demo'
        DEV_NAMESPACE = 'devops-dev'
        PROD_NAMESPACE = 'devops-production'
        KUBECONFIG_CREDENTIAL_ID = 'k8s-cluster-config'
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
                withCredentials([usernamePassword(passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME', credentialsId: "$DOCKER_CREDENTIAL_ID")]) {
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
                sh '''
                    # 创建开发命名空间（如果不存在）
                    kubectl create namespace $DEV_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

                    # 部署应用到开发环境
                    sed -i "s#REGISTRY#$REGISTRY#" deploy/cicd-demo-dev.yaml
                    sed -i "s#DOCKERHUB_NAMESPACE#$DOCKERHUB_NAMESPACE#" deploy/cicd-demo-dev.yaml
                    sed -i "s#APP_NAME#$APP_NAME#" deploy/cicd-demo-dev.yaml
                    sed -i "s#BUILD_NUMBER#$BUILD_NUMBER#" deploy/cicd-demo-dev.yaml
                    kubectl apply -f deploy/cicd-demo-dev.yaml -n $DEV_NAMESPACE

                    # 验证部署状态
                    kubectl rollout status deployment/$APP_NAME -n $DEV_NAMESPACE --timeout=300s
                '''
            }
        }

        stage('push with tag') {
            when {
                expression { return params.TAG_NAME =~ /v.*/ }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: "$GIT_CREDENTIAL_ID", passwordVariable: 'GIT_PASSWORD', usernameVariable: 'GIT_USERNAME')]) {
                    sh 'git config --global user.email "liulu@gitlab.cn"'
                    sh 'git config --global user.name "liulu"'
                    sh 'git tag -a $TAG_NAME -m "$TAG_NAME"'
                    sh "git push https://$GIT_USERNAME:$GIT_PASSWORD@$GIT_REPO_URL/$GIT_ACCOUNT/k8s-cicd-demo.git --tags --ipv4"
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
                    sed -i "s#REGISTRY#$REGISTRY#" deploy/cicd-demo.yaml
                    sed -i "s#DOCKERHUB_NAMESPACE#$DOCKERHUB_NAMESPACE#" deploy/cicd-demo.yaml
                    sed -i "s#APP_NAME#$APP_NAME#" deploy/cicd-demo.yaml
                    sed -i "s#TAG_NAME#$TAG_NAME#" deploy/cicd-demo.yaml
                    kubectl apply -f deploy/cicd-demo.yaml -n $PROD_NAMESPACE

                    # 验证部署状态
                    kubectl rollout status deployment/$APP_NAME -n $PROD_NAMESPACE --timeout=300s
                '''
            }
        }
    }
}
```

项目代码比较简单写了一个监听 `GET /users` 请求的控制器，旨在测试流水的工作状态

![image](https://github.com/user-attachments/assets/acb0da9b-8e4c-4c65-ada3-c1a0f3d162d7)


构建完毕后通过service查看暴露的nodeport端口测试访问

![image](https://github.com/user-attachments/assets/5f8b55d4-875f-4b81-b658-334d751f303d)


可以看到访问成功，那么以上便是devops流水线项目搭建的全过程，感谢您的阅读
