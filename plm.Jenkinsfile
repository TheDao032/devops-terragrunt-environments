pipeline {
    parameters {
      choice(
          name: 'terraform_module',
          choices: ['', 'vault-secrets', 'jenkins', 'kafka', 'prometheus', 'consul', 'vault'],
          description: 'Select one of the options'
      )
    }
    agent {
      label 'k3s-agent'
    }
    environment {
        LOCATION = 'on-prem' // Set LOCATION as 'on-prem'
        ENVIRONMENT = "${env.GIT_BRANCH}" // Dynamically get the Git branch
        VAULT_ADDR = credentials('vault-cluster-addr')
        VAULT_TOKEN = credentials('vault-token')
        HELM_REPO_URL = "https://github.com/TheDao032/devops-helm"
    }
    stages {
        stage('Terragrunt build') {
            steps {
                script {
                    def terraformModule = params.terraform_module
                    sh """
                    cd terragrunt-environments
                    chmod +x -R deployments

                    if [[ -n "${terraformModule}" ]]; then
                      deployments/${LOCATION}/build.sh ${ENVIRONMENT} ${terraformModule}
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
                    def terraformModule = params.terraform_module
                    sh """
                    cd terragrunt-environments

                    if [[ -n "${terraformModule}" ]]; then
                      deployments/${LOCATION}/deploy.sh ${ENVIRONMENT} ${terraformModule}
                    else
                      deployments/${LOCATION}/deploy.sh ${ENVIRONMENT}
                    fi
                    """
                }
            }
        }

        stage('Checkout Helm-Chart') {
            steps {
                script {
                    // Checkout another repository dynamically
                    def repoUrl = '${HELM_REPO_URL}'
                    def branch = '${ENVIRONMENT}'

                    dir('helm-chart') { // Clone into a subdirectory to avoid conflicts
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: "*/${branch}"]],
                            userRemoteConfigs: [[url: repoUrl]]
                        ])
                    }

                    echo "Checked out the additional repository."
                }
            }
        }

        stage('Execute deploy.sh from Helm-Chart Repo') {
            steps {
                script {
                    dir('helm-chart') {
                        sh """
                        chmod +x deploy.sh
                        ./deploy.sh
                        """
                    }
                }
            }
        }
    }

    // post {
    //     always {
    //         script {
    //             sh """
    //             cd terragrunt-environments
    //             if [[ -n "${TERRAFORM_MODULE}" ]]; then
    //               deployments/${LOCATION}/post.sh ${ENVIRONMENT} ${params.terraform_module}
    //             else
    //               deployments/${LOCATION}/post.sh ${ENVIRONMENT}
    //             fi
    //             """
    //         }
    //     }
    // }
}
