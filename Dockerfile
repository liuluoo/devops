## 基础镜像
## AdoptOpenJDK 停止发布 OpenJDK 二进制，而 Eclipse Temurin 是它的延伸，提供更好的稳定性
FROM eclipse-temurin:21-jre

## 创建并进入工作目录
RUN mkdir -p /liulu
WORKDIR /liulu

## maven 插件构建时得到 buildArgs 种的值
COPY target/*.jar app.jar

## 设置 TZ 时区
## 设置 JAVA_OPTS 环境变量，可通过 docker run -e "JAVA_OPTS=" 进行覆盖
ENV TZ=Asia/Shanghai JAVA_OPTS="-Xms512m -Xmx1024m"

## 暴露端口
EXPOSE 8080

## 容器启动命令
## CMD 第一个参数之后的命令可以在运行时被替换
CMD java ${JAVA_OPTS} -Djava.security.egd=file:/dev/./urandom -jar app.jar
