pipeline {
    agent any

    environment {
      LOCATION = "on-prem" // Set LOCATION as 'on-prem'
      ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
      // CREDENTIAL_IDS = ["k3s-env", "agile-app-env", "agile-db-env",
      //                   "agile-db-env", "hikari-conn-env", "ldap-env",
      //                   "pod-restart-collector-env", "query-env", "vault-env"]
      REGISTRY = "https://index.docker.io/v1/"
      IMAGE = "nthedao/infra-v1"
      TAG = "${env.GIT_COMMIT}"
      // VAULT_ADDR = credentials('vault-cluster-addr')
      // VAULT_TOKEN = credentials('vault-token')
      // HELM_REPO_URL = "https://github.com/TheDao032/devops-helm"
    }
    stages {
        stage('Build and Push Docker Image') {
            steps {
                script {
                    docker.withRegistry("${REGISTRY}", 'dockerhub-creds') {
                        def customImage = docker.build("${IMAGE}:${TAG}")
                        customImage.push()
                        customImage.push('latest')
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
