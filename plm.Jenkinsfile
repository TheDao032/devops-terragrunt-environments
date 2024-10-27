pipeline {
    agent {
      label 'k3s-agent'
    }
    environment {
        LOCATION = 'on-prem' // Set LOCATION as 'on-prem'
        ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
        VAULT_ADDR = credentials('vault-cluster-addr')
        VAULT_TOKEN = credentials('vault-token')
        TERRAFORM_MODULE = ${TERRAFORM_MODULE}
    }
    stages {
        input(
          message: 'Please choose an option:',
          parameters: [
              choice(choices: 'jenkins\nkafka\nprometheus\nvault-secrets',
                     description: 'Select one of the options',
                     name: 'UserChoice')
          ]
        )
        stage('Terragrunt build') {
            steps {
                script {
                    sh '''
                    cd terragrunt-environments

                    if [[ -n "${TERRAFORM_MODULE}" ]]; then
                      deployments/${LOCATION}/build.sh ${ENVIRONMENT} ${TERRAFORM_MODULE}
                    else
                      deployments/${LOCATION}/build.sh ${ENVIRONMENT}
                    fi
                    '''
                }
            }
        }
        stage('Terragrunt deploy') {
            steps {
                input(message: 'Proceed with Terragrunt apply?') // Optional for manual approval
                script {
                    sh '''
                    cd terragrunt-environments

                    if [[ -n "${TERRAFORM_MODULE}" ]]; then
                      deployments/${LOCATION}/deploy.sh ${ENVIRONMENT} ${TERRAFORM_MODULE}
                    else
                      deployments/${LOCATION}/deploy.sh ${ENVIRONMENT}
                    fi
                    '''
                }
            }
        }
    }

    // post {
    //     always {
    //         script {
    //             sh '''
    //             cd terragrunt-environments
    //             deployments/${LOCATION}/deploy.sh ${ENVIRONMENT}
    //             '''
    //         }
    //     }
    // }
}
