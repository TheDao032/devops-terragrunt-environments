pipeline {
    agent {
      label 'k3s-agent'
    }
    environment {
        KUBE_HOST = credentials('cluster-endpoint')
        KUBE_CLIENT_KEY = credentials('client-key') // Store in Jenkins credentials
        KUBE_CLIENT_CRT = credentials('client-crt') // Store in Jenkins credentials
        KUBE_CA_CRT = credentials('client-ca-crt') // Store in Jenkins credentials
    }
    stages {
        stage('Setup kubectl') {
            steps {
                script {
                    // Configure kubectl to use host and certificates
                    sh '''
                    echo "$KUBE_CLIENT_KEY" > /tmp/client.key
                    echo "$KUBE_CLIENT_CRT" > /tmp/client.crt
                    echo "$KUBE_CA_CRT" > /tmp/ca.crt

                    kubectl config set-cluster my-cluster --server=$KUBE_HOST --certificate-authority=/tmp/ca.crt
                    kubectl config set-credentials admin --client-key=/tmp/client.key --client-certificate=/tmp/client.crt
                    kubectl config set-context my-context --cluster=my-cluster --user=admin
                    kubectl config use-context my-context
                    '''
                }
            }
        }
        stage('Terragrunt Init') {
            steps {
                script {
                    sh '''
                    cd ${LOCATION}/${ENVIRONMENT} && terragrunt run-all init
                    '''
                }
            }
        }
        stage('Terragrunt Plan') {
            steps {
                script {
                    sh '''
                    cd ${LOCATION}/${ENVIRONMENT} && terragrunt run-all plan
                    '''
                }
            }
        }
        stage('Terragrunt Apply') {
            steps {
                input(message: 'Proceed with Terragrunt apply?') // Optional for manual approval
                script {
                    sh '''
                    cd ${LOCATION}/${ENVIRONMENT} && terragrunt run-all apply -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies
                    '''
                }
            }
        }
    }
    // post {
    //     always {
    //         script {
    //             sh 'cd ${LOCATION}/${ENVIRONMENT} && terragrunt run-all output'
    //         }
    //     }
    // }
}
