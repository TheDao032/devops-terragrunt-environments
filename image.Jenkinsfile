pipeline {
    agent {
        // kubernetes {
        //     yaml """
        //         apiVersion: v1
        //         kind: Pod
        //         metadata:
        //           labels:
        //             jenkins-agent: docker
        //         spec:
        //           containers:
        //           - name: docker
        //             image: docker:28.1.0-rc.1-dind
        //             command:
        //               - dockerd-entrypoint.sh
        //             args:
        //               - --host=unix:///var/run/docker.sock
        //               - --iptables=false
        //               - --ip-masq=false
        //             tty: true
        //             securityContext:
        //               privileged: true
        //             volumeMounts:
        //               - name: dind-storage
        //                 mountPath: /var/lib/docker
        //           volumes:
        //             - name: dind-storage
        //               persistentVolumeClaim:
        //                 claimName: jenkins-pipeline-pvc
        //     """
        // }
        kubernetes {
          inheritFrom 'docker'
        }
    }

    environment {
        LOCATION    = "on-prem"                  // Set LOCATION as 'on-prem'
        ENVIRONMENT = "${env.GIT_BRANCH}"          // Dynamically get the Git branch
        REGISTRY    = "https://index.docker.io/v1/"
        IMAGE       = "nthedao/infra-v1"
        TAG         = "${env.GIT_COMMIT}"
    }

    stages {
        stage('Build and Push Docker Image') {
            steps {
                container('docker') {
                    script {
                        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                            usernameVariable: 'DOCKERHUB_USERNAME',
                                                            passwordVariable: 'DOCKERHUB_PASSWORD')]) {
                            // Using --password-stdin is a best practice so the password does not appear on the command line.
                            sh """
                                echo "\$DOCKERHUB_PASSWORD" | docker login -u "\$DOCKERHUB_USERNAME" --password-stdin \$REGISTRY
                                docker build -t \$IMAGE:\$TAG -f Dockerfile .
                                docker push \$IMAGE:\$TAG
                                docker tag \$IMAGE:\$TAG \$IMAGE:latest
                                docker push \$IMAGE:latest
                            """
                        }
                    }
                }
            }
        }
    }
}

// def loadSecrets (Closure body, List<String> credentialIds) {
//     def credentialList = []
//     credentialIds.each {
//         credId -> credentialList.add(file(credentialsId: credId, variable: "${credId.toUpperCase()}_FILE"))
//     }
//
//     withCredentials(credentialList) {
//         // Load environment variables from secret files
//         sh """
//         set -a
//         ${credentialIds.collect { "source \$${it.toUpperCase()}_FILE" }.join('\n')}
//         set +a
//         """
//         // Run the provided body of steps (passed in closure)
//         body()
//     }
// }
