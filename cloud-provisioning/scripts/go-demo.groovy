node("docker") 
{
    stage("Pull") 
    {
        git "https://github.com/oceanexplorer/todo-api-demo.git"
    }
    
    withEnv([
        "COMPOSE_FILE=docker-compose-test-local.yml"
    ]) 
    {
        
        stage("Unit") 
        {
            sh "docker-compose run --rm unit"
            sh "docker-compose build app"
        }
    
        stage("Staging") 
        {
            try 
            {
                sh "docker-compose up -d staging-dep"
                sh "docker-compose run --rm staging"
            }
            catch (e) 
            {
                error "Staging failed"
            }
            finally 
            {
                sh "docker-compose down"
            }
        }

        stage("Publish") 
        {
            sh "docker tag oceanexplorer/todoapi localhost:5000/oceanexplorer/todoapi:2.${env.BUILD_NUMBER}"
            sh "docker push localhost:5000/oceanexplorer/todoapi:2.${env.BUILD_NUMBER}"
        }
    
        stage("Prod-like") 
        {
            withEnv([
                "DOCKER_TLS_VERIFY=1",
                "DOCKER_HOST=tcp://${env.PROD_LIKE_IP}:2376",
                "DOCKER_CERT_PATH=/machines/${env.PROD_LIKE_NAME}"]) 
            {
                sh "docker service update --image localhost:5000/oceanexplorer/todoapi:2.${env.BUILD_NUMBER} todoapi"
            }
            
            withEnv(["HOST_IP=localhost"]) 
            {
                try 
                {
                    for(i = 0; i < 10; i++) 
                    {
                        sh "docker-compose run --rm production"
                    }
                }
                catch (e) 
                {
                    sh "docker service update --rollback todoapi"
                }
            }
        }
    
        stage("Production") 
        {
            withEnv([
                "DOCKER_TLS_VERIFY=1",
                "DOCKER_HOST=tcp://${env.PROD_IP}:2376",
                "DOCKER_CERT_PATH=/machines/${env.PROD_NAME}"]) 
            {
                sh "docker service update --image localhost:5000/oceanexplorer/todoapi:2.${env.BUILD_NUMBER} todoapi"
            }
            
            try 
            {
                withEnv(["HOST_IP=${env.PROD_IP}"]) 
                {
                    for(i = 0; i < 10; i++) 
                    {
                        sh "docker-compose run --rm production"
                    }
                }
            }
            catch (e) 
            {
                withEnv([
                    "DOCKER_TLS_VERIFY=1",
                    "DOCKER_HOST=tcp://${env.PROD_IP}:2376",
                    "DOCKER_CERT_PATH=/machines/${env.PROD_NAME}"]) 
                {
                    sh "docker service update --rollback todoapi"
                }
            }
        }
    }
}