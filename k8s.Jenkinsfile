pipeline {
  parameters {
    choice(
        name: 'terraform_module',
        choices: ['', 'vault-secrets', 'jenkins', 'kafka', 'prometheus', 'consul', 'vault'],
        description: 'Select one of the options'
    )
  }
  agent {
    kubernetes {
        yaml """
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            jenkins-agent: terragrunt
        spec:
          containers:
          - name: terragrunt
            image: alpine/terragrunt:latest
            command:
            - cat
            tty: true
            resources:
              requests:
                memory: "512Mi"
                cpu: "500m"
              limits:
                memory: "1Gi"
                cpu: "1"
            volumeMounts:
            - name: docker-sock
              mountPath: /var/run/docker.sock
          volumes:
          - name: docker-sock
            hostPath:
              path: /var/run/docker.sock
        """
    }
  }

  environment {
    LOCATION = 'on-prem' // Set LOCATION as 'on-prem'
    ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
    CREDENTIAL_IDS = ["k3s-env", "agile-app-env", "agile-db-env",
                      "agile-db-env", "hikari-conn-env", "ldap-env",
                      "pod-restart-collector-env", "query-env", "vault-env"]
    // VAULT_ADDR = credentials('vault-cluster-addr')
    // VAULT_TOKEN = credentials('vault-token')
    // HELM_REPO_URL = "https://github.com/TheDao032/devops-helm"
  }
  stages {
    stage('Setup kubernetes config') {
        steps {
            script {
                withVault([
                    vaultSecrets: [
                        [
                            path: "${ENVIRONMENT}/data/k3s/creds",
                            engineVersion: 2,
                            secretValues: [
                                [envVar: 'KUBE_HOST', vaultKey: 'host'],
                                [envVar: 'KUBE_CLIENT_KEY_DATA', vaultKey: 'client_key'],
                                [envVar: 'KUBE_CLIENT_CERT_DATA', vaultKey: 'client_crt'],
                                [envVar: 'KUBE_CLUSTER_CA_CERT_DATA', vaultKey: 'client_ca_crt'],
                                [envVar: 'KUBE_TOKEN', vaultKey: 'token']
                            ]
                        ]
                    ],
                    vaultCredentialId: 'vault-jenkins-token'
                ]) {
                    container('terragrunt') {
                        script {
                            // Configure kubectl to use host and certificates
                            sh """
                            echo "${KUBE_CLIENT_KEY_DATA}" > /tmp/client.key
                            echo "${KUBE_CLIENT_CERT_DATA}" > /tmp/client.crt
                            echo "${KUBE_CLUSTER_CA_CERT_DATA}" > /tmp/ca.crt

                            kubectl config set-cluster ${ENVIRONMENT}-cluster --server=${KUBE_HOST} --certificate-authority=/tmp/ca.crt
                            kubectl config set-credentials admin --client-key=/tmp/client.key --client-certificate=/tmp/client.crt
                            kubectl config set-context ${ENVIRONMENT}-context --cluster=${ENVIRONMENT}-cluster --user=admin
                            kubectl config use-context ${ENVIRONMENT}-context
                            """
                        }
                    }
                }
            }
        }
    }

    stage('Terragrunt build') {
        steps {
            script {
                sh """
                if [[ -n "${TERRAFORM_MODULE}" ]]; then
                  deployments/${LOCATION}/build.sh ${ENVIRONMENT} ${params.terraform_module}
                else
                  deployments/${LOCATION}/build.sh ${ENVIRONMENT}
                fi
                """
            }
        }
    }
    stage('Terragrunt deploy') {
        steps {
            input(message: 'Proceed with Terragrunt apply?') // Optional for manual approval
            script {
                sh """
                if [[ -n "${TERRAFORM_MODULE}" ]]; then
                  deployments/${LOCATION}/deploy.sh ${ENVIRONMENT} ${params.terraform_module}
                else
                  deployments/${LOCATION}/deploy.sh ${ENVIRONMENT}
                fi
                """
            }
        }
    }
    // stage('Checkout Helm-Chart') {
    //     steps {
    //         script {
    //             // Checkout another repository dynamically
    //             def repoUrl = '${HELM_REPO_URL}'
    //             def branch = '${ENVIRONMENT}'
    //
    //             dir('helm-chart') { // Clone into a subdirectory to avoid conflicts
    //                 checkout([
    //                     $class: 'GitSCM',
    //                     branches: [[name: "*/${branch}"]],
    //                     userRemoteConfigs: [[url: repoUrl]]
    //                 ])
    //             }
    //
    //             echo "Checked out the additional repository."
    //         }
    //     }
    // }

    // stage('Execute deploy.sh from Helm-Chart Repo') {
    //     steps {
    //         script {
    //             dir('helm-chart') {
    //                 sh """
    //                 chmod +x deploy.sh
    //                 ./deploy.sh
    //                 """
    //             }
    //         }
    //     }
    // }
  }

  // post {
  //     always {
  //         script {
  //             sh '''
  //               if [[ -n "${TERRAFORM_MODULE}" ]]; then
  //                 deployments/${LOCATION}/deploy.sh ${ENVIRONMENT} ${params.terraform_module}
  //               else
  //                 deployments/${LOCATION}/deploy.sh ${ENVIRONMENT}
  //               fi
  //             '''
  //         }
  //     }
  // }
}

def loadSecrets (Closure body, List<String> credentialIds) {
    def credentialList = []
    credentialIds.each {
        credId -> credentialList.add(file(credentialsId: credId, variable: "${credId.toUpperCase()}_FILE"))
    }

    withCredentials(credentialList) {
        // Load environment variables from secret files
        sh """
        set -a
        ${credentialIds.collect { "source \$${it.toUpperCase()}_FILE" }.join('\n')}
        set +a
        """
        // Run the provided body of steps (passed in closure)
        body()
    }
}
