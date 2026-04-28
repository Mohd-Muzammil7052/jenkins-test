pipeline {
    agent {
        label 'linux'
    }

    options {
        timestamps()
    }

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_DEFAULT_REGION = 'ap-south-1' 

        ACCOUNT_ID = '169984788524'
        ECR_REPO = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/my-app"

        ECS_CLUSTER = 'my-cluster'
        ECS_SERVICE = 'my-service'
        TASK_FAMILY = 'my-task'

        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }

    stages {

        // ───────────── Build Jar File ─────────────
        stage('Build JAR') {
            steps {
                sh '''
                chmod +x mvnw
                ./mvnw clean package -DskipTests
                ls -l target
                '''
            }
        }

        // ───────────── Build Docker Image ─────────────
        stage('Build Image') {
            steps {
                sh '''
                docker build -t my-app:$IMAGE_TAG .
                docker images
                '''
            }
        }

        // ───────────── Push to ECR ─────────────
        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-DEP-team2-creds'
                ]]) {
                    sh '''
                    echo "Logging into ECR..."
                    aws ecr get-login-password --region $AWS_REGION \
                    | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

                    echo "Tagging image..."
                    docker tag my-app:$IMAGE_TAG $ECR_REPO:$IMAGE_TAG

                    echo "Pushing image..."
                    docker push $ECR_REPO:$IMAGE_TAG
                    '''
                }
            }
        }

        // ───────────── Prepare Task Definition ─────────────
        stage('Prepare Task Definition') {
            steps {
                sh '''
cat > task-def.json <<EOF
{
  "family": "$TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "my-app",
      "image": "$ECR_REPO:$IMAGE_TAG",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -q -O - http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      }
    }
  ]
}
EOF

echo "====== TASK DEF ======"
cat task-def.json
echo "======================"
                '''
            }
        }

        // ───────────── Register Task Definition ─────────────
        stage('Register Task Definition') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-DEP-team2-creds'
                ]]) {
                    script {
                        env.TASK_REVISION = sh(
                            script: '''
                            aws ecs register-task-definition \
                            --region $AWS_REGION \
                            --cli-input-json file://task-def.json \
                            --query 'taskDefinition.revision' \
                            --output text
                            ''',
                            returnStdout: true
                        ).trim()

                        echo "Registered Task Revision: ${env.TASK_REVISION}"
                    }
                }
            }
        }

        // ───────────── Deploy to ECS ─────────────
        stage('Deploy to ECS') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-DEP-team2-creds'
                ]]) {
                    sh '''
                    echo "Deploying to ECS..."
                    aws ecs update-service \
                    --region $AWS_REGION \
                    --cluster $ECS_CLUSTER \
                    --service $ECS_SERVICE \
                    --task-definition $TASK_FAMILY:$TASK_REVISION \
                    --force-new-deployment
                    '''
                }
            }
        }

        // ───────────── Wait for Stable Deployment ─────────────
        stage('Wait for Deployment') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-DEP-team2-creds'
                ]]) {
                    sh '''
                    echo "Waiting for ECS service to stabilize..."
                    aws ecs wait services-stable \
                    --region $AWS_REGION \
                    --cluster $ECS_CLUSTER \
                    --services $ECS_SERVICE
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ Deployment successful!"
        }
        failure {
            echo "❌ Deployment failed!"
        }
    }
}
