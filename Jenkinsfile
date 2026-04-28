pipeline {
    agent {
        label 'linux'
    }

    options {
        timestamps()
        disableConcurrentBuilds()               // prevent overlapping deployments
        buildDiscarder(logRotator(numToKeepStr: '10')) // keep last 10 builds
    }

    environment {
        AWS_REGION         = 'ap-south-1'
        AWS_DEFAULT_REGION = 'ap-south-1'

        ACCOUNT_ID  = '169984788524'
        ECR_REPO    = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/my-app"

        ECS_CLUSTER = 'my-cluster'
        ECS_SERVICE = 'my-service'
        TASK_FAMILY = 'my-task'

        EXECUTION_ROLE_ARN = "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole"
        TASK_ROLE_ARN      = "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskRole"

        IMAGE_TAG = "${env.BUILD_NUMBER}"

        // true when branch is main, master, or release/*
        IS_DEPLOY_BRANCH = "${env.GIT_BRANCH ==~ /(origin\/main|origin\/master|origin\/release\/.*)/ ? 'true' : 'false'}"
    }

    stages {

        // ───────────── Branch Info ─────────────
        stage('Branch Info') {
            steps {
                script {
                    env.GIT_BRANCH_NAME = sh(
                        script: 'git log -1 --format=%D | grep -oP "origin/\\K[^ ,]+"',
                        returnStdout: true
                        ).trim()

                    env.IS_DEPLOY_BRANCH = (env.GIT_BRANCH_NAME ==~ /(main|master|release\/.*)/) ? 'true' : 'false'

                    echo "Branch: ${env.GIT_BRANCH_NAME}"
                    echo "CD will run: ${env.IS_DEPLOY_BRANCH}"
                }
            }
        }

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
                '''
            }
        }

        // ───────────── Push to ECR ─────────────
        // Only push if on a deploy branch
        stage('Push to ECR') {
            when {
                expression { env.IS_DEPLOY_BRANCH == 'true' }
            }
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
            when {
                expression { env.IS_DEPLOY_BRANCH == 'true' }
            }
            steps {
                script {
                    def taskDef = """{
  "family": "${env.TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${env.EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${env.TASK_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "my-app",
      "image": "${env.ECR_REPO}:${env.IMAGE_TAG}",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-task",
          "awslogs-region": "${env.AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -q -O - http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}"""
                    writeFile file: 'task-def.json', text: taskDef
                    sh '''
                    echo "====== TASK DEF ======"
                    cat task-def.json
                    echo "======================"
                    '''
                }
            }
        }

        // ───────────── Register Task Definition ─────────────
        stage('Register Task Definition') {
            when {
                expression { env.IS_DEPLOY_BRANCH == 'true' }
            }
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
            when {
                expression { env.IS_DEPLOY_BRANCH == 'true' }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-DEP-team2-creds'
                ]]) {
                    sh """
                    echo "Deploying task def: ${env.TASK_FAMILY}:${env.TASK_REVISION}"
                    aws ecs update-service \
                        --region ${env.AWS_REGION} \
                        --cluster ${env.ECS_CLUSTER} \
                        --service ${env.ECS_SERVICE} \
                        --task-definition ${env.TASK_FAMILY}:${env.TASK_REVISION} \
                        --health-check-grace-period-seconds 120 \
                        --force-new-deployment
                    """
                }
            }
        }

        // ───────────── Wait for Stable Deployment ─────────────
        stage('Wait for Deployment') {
            when {
                expression { env.IS_DEPLOY_BRANCH == 'true' }
            }
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

        // ───────────── Cleanup Old Docker Images ─────────────
        stage('Cleanup') {
            steps {
                sh '''
                echo "Removing dangling images..."
                docker image prune -f
                '''
            }
        }
    }

    post {
        success {
            script {
                if (env.IS_DEPLOY_BRANCH == 'true') {
                    echo "✅ Build + Deployment successful on branch: ${env.BRANCH_NAME}"
                } else {
                    echo "✅ Build successful on branch: ${env.BRANCH_NAME} (CD skipped — not a deploy branch)"
                }
            }
        }
        failure {
            echo "❌ Pipeline failed on branch: ${env.BRANCH_NAME}"
        }
        always {
            // Clean workspace after every build
            cleanWs()
        }
    }
}
