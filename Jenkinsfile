pipeline {
    agent any

    environment {
        // Define environment variables
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key') // Stored in Jenkins Credentials
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-key')
        VPC_ID                = 'vpc-0xxxxxx' // Replace with your VPC ID
        SUBNET_ID             = 'subnet-0xxxxxx' // Public subnet where Packer builds
        AWS_DEFAULT_REGION    = 'us-east-1'
        AMI_NAME              = "test1-app-ami-${currentBuild.number}-${env.BUILD_ID}"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/Consultlawal/test1.git '
            }
        }

        stage('Validate Packer Template') {
            steps {
                sh 'packer validate packer-ami.json'
            }
        }

        stage('Build Custom AMI') {
            steps {
                script {
                    // Inject AWS keys into environment
                    env.AWS_ACCESS_KEY_ID = AWS_ACCESS_KEY_ID
                    env.AWS_SECRET_ACCESS_KEY = AWS_SECRET_ACCESS_KEY

                    // Run Packer Build
                    sh """
                        cd ${WORKSPACE}
                        packer build \\
                          -var "aws_access_key=\${AWS_ACCESS_KEY_ID}" \\
                          -var "aws_secret_key=\${AWS_SECRET_ACCESS_KEY}" \\
                          -var "vpc_id=${VPC_ID}" \\
                          -var "subnet_id=${SUBNET_ID}" \\
                          -var "ami_name=${AMI_NAME}" \\
                          packer-ami.json
                    """
                }
            }
        }

        stage('Save AMI ID (Optional)') {
            steps {
                script {
                    // Save AMI ID to file or SSM Parameter Store
                    sh """
                        echo "Built AMI: ${AMI_NAME}"
                        echo "ami_name = \\"${AMI_NAME}\\"" > ami.auto.tfvars
                    """
                }
            }
        }

        stage('Apply Terraform (Optional)') {
            when {
                expression { env.TERRAFORM_DEPLOY == "true" }
            }
            steps {
                script {
                    dir("terraform") {
                        sh 'terraform apply -auto-approve -var-file="../ami.auto.tfvars"'
                    }
                }
            }
        }
    }

    post {
        success {
            echo "✅ Custom AMI built successfully: ${AMI_NAME}"
            slackSend channel: '#devops', color: '#6eba76', message: "✅ [Packer] AMI Built: ${AMI_NAME}"
        }
        failure {
            echo "❌ Packer build failed"
            slackSend channel: '#devops', color: '#ff0033', message: "❌ [Packer] AMI Build Failed"
        }
    }
}