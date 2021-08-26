## Create a new bedrock project

PROJECT_ID=bedrock-cloudrun-example
composer create-project roots/bedrock $PROJECT_ID
cd $PROJECT_ID

## Configure the project

cp ../bedrock-cloudrun-template/.editorconfig .
composer require wp-cli/wp-cli

## Local development

mysql -uroot <<EOD
drop database wordpress;
drop user wordpress;

create database wordpress;
create user 'wordpress' identified with mysql_native_password by 'wordpress';
grant all on wordpress.* to wordpress;
EOD

cat >.env <<EOD
DB_NAME=wordpress
DB_USER=wordpress
DB_PASSWORD=wordpress
WP_ENV=development
WP_SITEURL=http://localhost:8080/wp
WP_HOME=http://localhost:8080
EOD

## Confirm it works

php -S localhost:8080 -t web

## Configure the Docker build

cp ../bedrock-cloudrun-template/Dockerfile .
cp -rvn ../bedrock-cloudrun-template/config .
cp ../bedrock-cloudrun-template/.*ignore .
# view Dockerfile and configs

## Testing the build locally

docker build . -t foofoo
docker run -ti foofoo /bin/sh
docker run -ti -v $(pwd)/.env:/app/.env --env="DB_HOST=host.docker.internal" -p 8080:8080 foofoo

open http://localhost:8080/

## Create a GCP project and database

gcloud projects create $PROJECT_ID # eg.
gcloud beta billing projects link $PROJECT_ID --billing-account="0036F5-D057F4-1655F1"

gcloud config set project $PROJECT_ID
gcloud config set run/region europe-north1
gcloud config set run/platform managed

gcloud sql instances create wordpress --region="europe-north1"
gcloud sql databases create wordpress --instance="wordpress"
gcloud sql users create wordpress --instance="wordpress" --password="wordpress"

## Start sql proxy in another shell

cloud_sql_proxy -instances="${PROJECT_ID}:europe-north1:wordpress=tcp:33060"

## Testing the build locally, with remote db

docker run -ti -v $(pwd)/.env:/app/.env --env="DB_HOST=host.docker.internal:33060" -p 8080:8080 foofoo

## Remote build

gcloud builds submit --tag="gcr.io/$PROJECT_ID/app"
docker pull gcr.io/$PROJECT_ID/app

## Local build

docker build . --tag="gcr.io/$PROJECT_ID/app"
docker push gcr.io/$PROJECT_ID/app

## Cloud Run deployment

cp .env .env.cloudrun
gcloud secrets create dotenv --data-file=".env.cloudrun"

RUN_SERVICE_ACCOUNT="app-run"
gcloud iam service-accounts create $RUN_SERVICE_ACCOUNT
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${RUN_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:${RUN_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/cloudsql.client"

gcloud beta run deploy app \
  --image="gcr.io/$PROJECT_ID/app" \
  --set-cloudsql-instances="wordpress" \
  --set-secrets="/secrets/dotenv=dotenv:latest" \
  --set-env-vars="DB_HOST=:/cloudsql/${PROJECT_ID}:europe-north1:wordpress" \
  --allow-unauthenticated \
  --service-account="${RUN_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"

RUN_URL=$(gcloud run services describe app \
  --format="value(status.address.url)")

cat >>.env.cloudrun <<EOD
WP_SITEURL=$RUN_URL/wp
WP_HOME=$RUN_URL
EOD

gcloud secrets versions add dotenv \
    --data-file=".env.cloudrun"

gcloud run services update app --image="gcr.io/$PROJECT_ID/app"

## OPTION: Firebase init

open https://console.firebase.google.com/
firebase init hosting
rm web/index.html

# add to firebase.json hosting section
"rewrites": [ {
  "source": "**",
  "run": {
    "serviceId": "app",
    "region": "europe-north1"
  }
} ]

export RUN_URL=https://$PROJECT_ID.web.app  # eg.

cat >>.env.cloudrun <<EOD
WP_SITEURL=$RUN_URL/wp
WP_HOME=$RUN_URL
EOD

gcloud secrets versions add dotenv \
    --data-file=".env.cloudrun"

gcloud run services update app \
    --image="gcr.io/$PROJECT_ID/app"

## OPTION: host automatic discovery

# Edit config/application.php to do host auto discovery
# search for block with comment "URLs"

if (array_key_exists('HTTP_X_FORWARDED_PROTO',$_SERVER) && $_SERVER["HTTP_X_FORWARDED
_PROTO"] == 'https') $_SERVER['HTTPS'] = 'on';
$_server_http_host_scheme = array_key_exists('HTTPS',$_SERVER) && $_SERVER['HTTPS'] =
= 'on' ? 'https' : 'http';
$_server_http_host_name = array_key_exists('HTTP_HOST',$_SERVER) ? $_SERVER['HTTP_HOS
T'] : 'localhost';
$_server_http_url = "$_server_http_host_scheme://$_server_http_host_name";
Config::define('WP_HOME', env('WP_HOME') ?: "$_server_http_url");
Config::define('WP_SITEURL', env('WP_SITEURL') ?: "$_server_http_url/wp");

## OPTION: Batcache, Redis / Memcached, Auth0 etc.

composer require koodimonni/composer-dropin-installer
# add to composer.json extra:
    "dropin-paths": {
      "web/app": [
        "package:wpackagist-plugin/memcached-redux:object-cache.php",
        "package:wpackagist-plugin/batcache:advanced-cache.php",
        "type:wordpress-dropin"
      ]
    }

composer require wpackagist-plugin/batcache wpackagist-plugin/memcached-redux wpackagist-plugin/auth0 ## eg.

echo '/advanced-cache.php' >>web/app/.gitignore
echo '/object-cache.php' >>web/app/.gitignore

## OPTION: Cloud CDN

gcloud compute addresses create app-ip \
    --ip-version="IPV4" \
    --global

gcloud compute network-endpoint-groups create app-neg \
    --region="europe-north1" \
    --network-endpoint-type="serverless"  \
    --cloud-run-service="app"

gcloud compute backend-services create app-backend \
    --global --enable-cdn \
    --custom-response-header="Cache-Status: {cdn_cache_status}" \
    --custom-response-header="Cache-ID: {cdn_cache_id}"

gcloud compute backend-services add-backend app-backend \
    --global \
    --network-endpoint-group="app-neg" \
    --network-endpoint-group-region="europe-north1"

gcloud compute url-maps create app-lb \
    --default-service="app-backend"

gcloud compute target-http-proxies create app-http \
    --url-map="app-lb"

gcloud compute forwarding-rules create app-http-rule \
    --address="app-ip" --ports="80" \
    --target-http-proxy="app-http" \
    --global

APP_IP=$(gcloud compute addresses describe app-ip \
    --format="get(address)" \
    --global)

cat >>.env.cloudrun <<EOD
WP_SITEURL=http://$APP_IP/wp
WP_HOME=http://$APP_IP
EOD

gcloud secrets versions add dotenv \
    --data-file=".env.cloudrun"

gcloud run services update app \
    --image="gcr.io/$PROJECT_ID/app"

## OPTION: set min instances

gcloud run services update app \
    --image="gcr.io/$PROJECT_ID/app" \
    --min-instances="1"
