// pipeline {
//     agent {
//         // docker {
//         //     image 'docker:28.0.4-cli-alpine3.21' // Docker CLI image
//         //     args '-v /var/run/docker.sock:/var/run/docker.sock' // Mount Docker socket
//         // }
//         kubernetes {
//             yaml """
//             apiVersion: v1
//             kind: Pod
//             metadata:
//               labels:
//                 jenkins-agent: docker
//             spec:
//               containers:
//               - name: docker
//                 image: docker:28.0.4
//                 tty: true
//                 resources:
//                   requests:
//                     memory: "512Mi"
//                     cpu: "500m"
//                   limits:
//                     memory: "1Gi"
//                     cpu: "1"
//                 volumeMounts:
//                 - name: docker-sock
//                   mountPath: /var/run/docker.sock
//               volumes:
//               - name: docker-sock
//                 hostPath:
//                   path: /var/run/docker.sock
//             """
//         }
//
//     }
//
//     environment {
//       LOCATION = "on-prem" // Set LOCATION as 'on-prem'
//       ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
//       // CREDENTIAL_IDS = ["k3s-env", "agile-app-env", "agile-db-env",
//       //                   "agile-db-env", "hikari-conn-env", "ldap-env",
//       //                   "pod-restart-collector-env", "query-env", "vault-env"]
//       REGISTRY = "https://index.docker.io/v1/"
//       IMAGE = "nthedao/infra-v1"
//       TAG = "${env.GIT_COMMIT}"
//       // VAULT_ADDR = credentials('vault-cluster-addr')
//       // VAULT_TOKEN = credentials('vault-token')
//       // HELM_REPO_URL = "https://github.com/TheDao032/devops-helm"
//     }
//     stages {
//         stage('Build and Push Docker Image') {
//             steps {
//                 script {
//                     // docker.withRegistry("${REGISTRY}", 'dockerhub-creds') {
//                     //     def dockerfile = 'Dockerfile'
//                     //     def customImage = docker.build("${IMAGE}:${TAG}", "-f ${dockerfile} ./")
//                     //     customImage.push()
//                     //     customImage.push('latest')
//                     // }
//                     withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD')]) {
//                         sh """
//                             echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin $REGISTRY
//                             docker build -t $IMAGE:$TAG .
//                             docker push $IMAGE:$TAG
//                             docker push $IMAGE:latest
//                         """
//                     }
//                 }
//             }
//         }
//     }
// }
//
// // def loadSecrets (Closure body, List<String> credentialIds) {
// //     def credentialList = []
// //     credentialIds.each {
// //         credId -> credentialList.add(file(credentialsId: credId, variable: "${credId.toUpperCase()}_FILE"))
// //     }
// //
// //     withCredentials(credentialList) {
// //         // Load environment variables from secret files
// //         sh """
// //         set -a
// //         ${credentialIds.collect { "source \$${it.toUpperCase()}_FILE" }.join('\n')}
// //         set +a
// //         """
// //         // Run the provided body of steps (passed in closure)
// //         body()
// //     }
// // }

pipeline {
    agent {
        kubernetes {
            yaml """
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    jenkins-agent: docker
                spec:
                  containers:
                  - name: docker
                    image: docker:28.1.0-rc.1-dind
                    command:
                      - dockerd-entrypoint.sh
                    args:
                      - --host=unix:///var/run/docker.sock
                      - --iptables=false
                      - --ip-masq=false
                    tty: true
                    securityContext:
                      privileged: true
                    volumeMounts:
                      - name: dind-storage
                        mountPath: /var/lib/docker
                  volumes:
                    - name: dind-storage
                      emptyDir: {}
            """
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
                                dockerd-entrypoint.sh &
                                sleep 5
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
