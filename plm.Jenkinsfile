pipeline {
    parameters {
        choice(
            name: 'tenant',
            choices: ['bosch', 'renesas'],
            description: 'Tenant whose terragrunt env tree should be applied'
        )
        choice(
            name: 'terraform_module',
            choices: ['', 'vault-secrets', 'jenkins', 'kafka', 'prometheus', 'consul', 'vault'],
            description: 'Single module to apply (empty = run-all under the tenant + env)'
        )
    }
    agent {
        label 'k3s-agent'
    }
    environment {
        LOCATION = 'on-prem' // Set LOCATION as 'on-prem'
        TENANT = "${params.tenant}"
        ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
        CREDENTIAL_IDS = ["k3s-env", "agile-app-env", "agile-db-env",
                          "agile-db-env", "hikari-conn-env", "ldap-env",
                          "pod-restart-collector-env", "query-env", "vault-env"]
    }
    stages {
        stage('Terragrunt build') {
            steps {
                script {
                    def credentialIdsList = CREDENTIAL_IDS
                    loadSecrets({
                        def terraformModule = params.terraform_module
                        sh """
                        cd terragrunt-environments
                        chmod +x -R deployments

                        if [[ -n "${terraformModule}" ]]; then
                          deployments/${LOCATION}/build.sh ${TENANT} ${ENVIRONMENT} ${terraformModule}
                        else
                          deployments/${LOCATION}/build.sh ${TENANT} ${ENVIRONMENT}
                        fi
                        """
                    }, credentialIdsList)
                }
            }
        }
        stage('Terragrunt deploy') {
            steps {
                input(message: 'Proceed with Terragrunt apply?') // Optional for manual approval
                script {
                    def credentialIdsList = CREDENTIAL_IDS

                    // Pass the list of credential IDs as an argument
                    loadSecrets({
                        def terraformModule = params.terraform_module
                        sh """
                        cd terragrunt-environments

                        if [[ -n "${terraformModule}" ]]; then
                          deployments/${LOCATION}/deploy.sh ${TENANT} ${ENVIRONMENT} ${terraformModule}
                        else
                          deployments/${LOCATION}/deploy.sh ${TENANT} ${ENVIRONMENT}
                        fi
                        """
                    }, credentialIdsList)
                }
            }
        }
    }

    // post {
    //     always {
    //         script {
    //             sh """
    //             cd terragrunt-environments
    //             if [[ -n "${params.terraform_module}" ]]; then
    //               deployments/${LOCATION}/post.sh ${TENANT} ${ENVIRONMENT} ${params.terraform_module}
    //             else
    //               deployments/${LOCATION}/post.sh ${TENANT} ${ENVIRONMENT}
    //             fi
    //             """
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
