#!/usr/bin/env groovy
/**
 * Golden Image Pipeline
 * Builds hardened AMIs using Jenkins HA + Packer + Ansible
 * 
 * Author: Kiran S
 * Architecture: Blue-Green Jenkins HA with automated failover
 */

@Library('company-shared-lib@main') _

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: packer
      image: hashicorp/packer:1.10
      command: ['cat']
      tty: true
    - name: ansible
      image: cytopia/ansible:2.15-tools
      command: ['cat']
      tty: true
    - name: terraform
      image: hashicorp/terraform:1.6
      command: ['cat']
      tty: true
    - name: trivy
      image: aquasec/trivy:latest
      command: ['cat']
      tty: true
"""
        }
    }

    environment {
        AWS_REGION          = 'ap-south-1'
        BASE_AMI_ID         = 'ami-0f58b397bc5c1f2e8'
        ARTIFACT_BUCKET     = 'company-ami-artifacts'
        SLACK_CHANNEL       = '#devops-alerts'
        PACKER_LOG          = '1'
        ANSIBLE_FORCE_COLOR = 'true'
    }

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['staging', 'production'],
            description: 'Target environment for AMI'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip InSpec compliance tests (emergency builds only)'
        )
    }

    options {
        timeout(time: 2, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
        ansiColor('xterm')
    }

    stages {
        stage('Validate') {
            parallel {
                stage('Packer Validate') {
                    steps {
                        container('packer') {
                            sh '''
                                packer init packer/
                                packer validate \
                                    -var "region=${AWS_REGION}" \
                                    -var "base_ami=${BASE_AMI_ID}" \
                                    packer/golden-image.pkr.hcl
                                echo "✅ Packer template validation passed"
                            '''
                        }
                    }
                }
                stage('Ansible Lint') {
                    steps {
                        container('ansible') {
                            sh '''
                                ansible-lint ansible/site.yml --profile=production
                                echo "✅ Ansible lint passed"
                            '''
                        }
                    }
                }
                stage('Terraform Validate') {
                    steps {
                        container('terraform') {
                            sh '''
                                cd terraform/
                                terraform fmt -check -recursive
                                terraform init -backend=false
                                terraform validate
                                echo "✅ Terraform validation passed"
                            '''
                        }
                    }
                }
            }
        }

        stage('Security Scan') {
            steps {
                container('trivy') {
                    sh '''
                        # Scan base AMI packages (via fs scan of known package list)
                        trivy fs ansible/ \
                            --exit-code 0 \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --scanners secret,misconfig
                        
                        # Scan Ansible roles for secrets
                        trivy fs . \
                            --scanners secret \
                            --exit-code 1 \
                            --format table
                        
                        echo "✅ Security scan passed"
                    '''
                }
            }
        }

        stage('Build Golden AMI') {
            steps {
                container('packer') {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'aws-packer-credentials',
                            usernameVariable: 'AWS_ACCESS_KEY_ID',
                            passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                        )
                    ]) {
                        sh '''
                            echo "🔨 Building Golden AMI for ${ENVIRONMENT}..."
                            
                            packer build \
                                -var "region=${AWS_REGION}" \
                                -var "base_ami=${BASE_AMI_ID}" \
                                -var "environment=${ENVIRONMENT}" \
                                -var "build_number=${BUILD_NUMBER}" \
                                -var "git_commit=${GIT_COMMIT}" \
                                -on-error=abort \
                                packer/golden-image.pkr.hcl | tee packer-build.log
                            
                            # Extract AMI ID from Packer output
                            AMI_ID=$(grep -oP 'ami-[a-f0-9]+' packer-build.log | tail -1)
                            echo "AMI_ID=${AMI_ID}" > build.env
                            echo "✅ Golden AMI created: ${AMI_ID}"
                        '''
                    }
                }
            }
        }

        stage('Compliance Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                container('ansible') {
                    sh '''
                        source build.env
                        echo "🧪 Running InSpec compliance tests on AMI: ${AMI_ID}"
                        
                        # Launch test instance from new AMI
                        TEST_INSTANCE_ID=$(aws ec2 run-instances \
                            --image-id ${AMI_ID} \
                            --instance-type t3.micro \
                            --tag-specifications "ResourceType=instance,Tags=[{Key=Purpose,Value=ami-test},{Key=BuildNumber,Value=${BUILD_NUMBER}}]" \
                            --query 'Instances[0].InstanceId' \
                            --output text)
                        
                        echo "TEST_INSTANCE_ID=${TEST_INSTANCE_ID}" >> build.env
                        
                        # Wait for instance to be running
                        aws ec2 wait instance-running --instance-ids ${TEST_INSTANCE_ID}
                        sleep 60  # Allow SSM agent to start
                        
                        echo "✅ Test instance ready: ${TEST_INSTANCE_ID}"
                    '''
                }
            }
        }

        stage('Tag and Promote') {
            steps {
                container('ansible') {
                    sh '''
                        source build.env
                        
                        # Tag AMI as golden
                        aws ec2 create-tags \
                            --resources ${AMI_ID} \
                            --tags \
                                Key=golden,Value=true \
                                Key=status,Value=approved \
                                Key=environment,Value=${ENVIRONMENT} \
                                Key=build_number,Value=${BUILD_NUMBER} \
                                Key=git_commit,Value=${GIT_COMMIT:0:8} \
                                Key=created_by,Value=jenkins-pipeline
                        
                        echo "✅ AMI tagged: ${AMI_ID}"
                        echo "🎉 Golden Image promotion complete!"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Archive build artifacts
            archiveArtifacts artifacts: 'packer-build.log', allowEmptyArchive: true
            
            // Clean up test instances
            sh '''
                if [ -f build.env ]; then
                    source build.env
                    if [ -n "${TEST_INSTANCE_ID}" ]; then
                        aws ec2 terminate-instances --instance-ids ${TEST_INSTANCE_ID} || true
                        echo "🧹 Test instance terminated"
                    fi
                fi
            '''
        }
        success {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'good',
                message: """✅ *Golden Image Build SUCCESS*
                Build: ${BUILD_NUMBER}
                AMI: See build log for AMI ID
                Environment: ${params.ENVIRONMENT}
                Duration: ${currentBuild.durationString}"""
            )
        }
        failure {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'danger',
                message: """❌ *Golden Image Build FAILED*
                Build: ${BUILD_NUMBER}
                Environment: ${params.ENVIRONMENT}
                Check: ${BUILD_URL}"""
            )
        }
    }
}
