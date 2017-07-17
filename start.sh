#!/bin/bash

echo "Inserting CIS Registry information into Rancher DB"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO setting (name, value) VALUES ('catalog.url','{\"catalogs\":{\"library\":{\"url\":\"https://git.rancher.io/rancher-catalog.git\",\"branch\":\"master\"},\"community\":{\"url\":\"https://git.rancher.io/community-catalog.git\",\"branch\":\"master\"},\"CIS\":{\"url\":\"https://github.com/livehybrid/CIS-Catalog\",\"branch\":\"master\"}}}');"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO storage_pool (name, account_id, kind, uuid, description, state, created, removed, remove_time, data, zone_id) VALUES (NULL, 5, 'registry', 'df3c15f4-b2d6-4dff-9fa8-5672e9ba9232', NULL, 'active', '2017-01-10 16:15:50', NULL, NULL, '{\"fields\":{\"serverAddress\":\"446537062602.dkr.ecr.eu-west-2.amazonaws.com\"}}' , 1);"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO credential (name, account_id, kind, uuid, description, state, created, removed, remove_time, data, public_value, secret_value, registry_id) VALUES (NULL, 5, 'registryCredential', '36c20ad5-e6df-44c0-a438-ba0ab7e9a272', NULL, 'active', '2017-01-10 16:01:23', NULL, NULL, '{\"fields\":{\"email\":\"not-really@required.anymore\"}}', 'TEST', 'TEST', 1);"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; UPDATE credential, storage_pool SET credential.registry_id = storage_pool.id WHERE storage_pool.uuid = 'df3c15f4-b2d6-4dff-9fa8-5672e9ba9232' AND credential.uuid = '36c20ad5-e6df-44c0-a438-ba0ab7e9a272';"

echo "Authenticating against Amazon ECR"
docker run --rm -e "AWS_REGION=eu-west-2" -e "CATTLE_URL=$RANCHER_URL" -e "CATTLE_ACCESS_KEY=$RANCHER_ACCESS_KEY" -e "CATTLE_SECRET_KEY=$RANCHER_SECRET_KEY" -l io.rancher.container.network=true -l io.rancher.container.pull_image=always -l io.rancher.container.create_agent='true' -l io.rancher.container.agent.role=environment livehybrid/rancher-ecr-credentials


echo "Set Access Control for a set of GitHib Users"
rancher_token="$RANCHER_ACCESS_KEY:$RANCHER_SECRET_KEY"
users=( $GITHUB_ACCESS_USERNAMES )
allowedEntitiesArray=()
for user in "${users[@]}"; do
  curlResp=$(curl https://api.github.com/users/$user)

  declare -A tempArray
  while IFS="=" read -r key value; do
    tempArray[$key]="$value"
  done < <(echo $curlResp | jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]")

  allowedEntitiesArray+=$(jq \
    --arg key0 'externalId' --arg value0 $tempArray[id] \
    --arg key1 'externalIdType' --arg value1 "github_user" \
    --arg key2 'name' --arg value2 $tempArray[login] \
    --arg key3 'login' --arg value3 $tempArray[login] \
    --arg key4 'profilePicture' --arg value4 $tempArray[avatar_url] \
    --arg key5 'profileUrl' --arg value5 $tempArray[html_url] \
    --arg key6 'type' --arg value6 "identity" \
    --arg key7 'user' --arg value7 true \
    --arg key8 'id' --arg value8 "github_user:"$tempArray[id] \
    '. | .[$key0]=$value0 | .[$key1]=$value1 | .[$key2]=$value2 | .[$key3]=$value3 | .[$key4]=$value4 | .[$key5]=$value5 | .[$key6]=$value6 | .[$key7]=$value7 | .[$key8]=$value8' <<< '{}')
done

allowedEntities=$(printf '%s\n' "${allowedEntitiesArray[@]}" | jq -s -c . | sed s/\"true\"/true/g)

curl \
  --url $RANCHER_URL/v1-auth/config \
  --user $rancher_token \
  --header 'content-type: application/json' \
  --data-binary '{"accessMode":"required","allowedIdentities":'$allowedEntities',"enabled":false,"githubConfig":{"clientId":"$GITHUB_CLIENT_ID","clientSecret":"$GITHUB_SERVER_ID","hostname":null,"links":null,"scheme":"https://","type":"githubconfig","actionLinks":null},"provider":"githubconfig","shibbolethConfig":{"IDPMetadataFilePath":"","RancherAPIHost":"","SPSelfSignedCertFilePath":"","SPSelfSignedKeyFilePath":"","SamlServiceProvider":null,"actions":null,"displayNameField":"","groupsField":"","idpMetadataContent":"","idpMetadataUrl":"","links":null,"spCert":"","spKey":"","uidField":"","userNameField":""},"type":"config"}'


echo "Enable each GitHub User to be an Admin"
allowedEntitiesArray=()
for user in "${users[@]}"; do
  tmpUuid=$(uuidgen)
  tmpTimeDate=$(date +"%F %T")

  curlResp=$(curl https://api.github.com/users/$user)

  declare -A tempArray
  while IFS="=" read -r key value; do
    tempArray[$key]="$value"
  done < <(echo $curlResp | jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]")

  docker exec \
    -it rancher-ha mysql \
    -h $MYSQL_HOST \
    -u $MYSQL_DBNAME \
    -p$MYSQL_PASS \
    $MYSQL_DBNAME \
    "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO account (name, kind, uuid, state, created, external_id, external_id_type, health_state, version, revision) VALUES ('${tempArray[login]}', 'admin', '${tmpUuid}', 'active', '$tmpTimeDate', '${tempArray[id]}', 'github_user', 'healthy', 2, 0);"
done


echo "Restarting Rancher"
docker restart rancher-ha
