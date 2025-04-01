FROM jenkins/jenkins:2.502-jdk21
ADD ./apache-maven-3.9.7-bin.tar.gz /usr/local/

USER root
WORKDIR /usr/local/

ENV MAVEN_HOME=/usr/local/apache-maven-3.9.7
ENV PATH=$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH

RUN echo "jenkins ALL=NOPASSWD: ALL" >> /etc/sudoers
USER jenkins
