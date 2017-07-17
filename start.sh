#!/bin/sh
echo "Inserting CIS Registry information into Rancher DB"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO setting (name, value) VALUES ('catalog.url','{\"catalogs\":{\"library\":{\"url\":\"https://git.rancher.io/rancher-catalog.git\",\"branch\":\"master\"},\"community\":{\"url\":\"https://git.rancher.io/community-catalog.git\",\"branch\":\"master\"},\"CIS\":{\"url\":\"https://github.com/livehybrid/CIS-Catalog\",\"branch\":\"master\"}}}');"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO storage_pool (name, account_id, kind, uuid, description, state, created, removed, remove_time, data, zone_id) VALUES (NULL, 5, 'registry', 'df3c15f4-b2d6-4dff-9fa8-5672e9ba9232', NULL, 'active', '2017-01-10 16:15:50', NULL, NULL, '{\"fields\":{\"serverAddress\":\"446537062602.dkr.ecr.eu-west-2.amazonaws.com\"}}' , 1);"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; INSERT INTO credential (name, account_id, kind, uuid, description, state, created, removed, remove_time, data, public_value, secret_value, registry_id) VALUES (NULL, 5, 'registryCredential', '36c20ad5-e6df-44c0-a438-ba0ab7e9a272', NULL, 'active', '2017-01-10 16:01:23', NULL, NULL, '{\"fields\":{\"email\":\"not-really@required.anymore\"}}', 'TEST', 'TEST', 1);"
docker exec -it rancher-ha mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DBNAME "-e" "SET FOREIGN_KEY_CHECKS = 0; UPDATE credential, storage_pool SET credential.registry_id = storage_pool.id WHERE storage_pool.uuid = 'df3c15f4-b2d6-4dff-9fa8-5672e9ba9232' AND credential.uuid = '36c20ad5-e6df-44c0-a438-ba0ab7e9a272';"

echo "Authenticating against Amazon ECR"
docker run --rm -e "AWS_REGION=eu-west-2" -e "CATTLE_URL=$RANCHER_URL" -e "CATTLE_ACCESS_KEY=$RANCHER_ACCESS_KEY" -e "CATTLE_SECRET_KEY=$RANCHER_SECRET_KEY" -l io.rancher.container.network=true -l io.rancher.container.pull_image=always -l io.rancher.container.create_agent='true' -l io.rancher.container.agent.role=environment livehybrid/rancher-ecr-credentials

echo "Restarting Rancher"
docker restart rancher-ha
