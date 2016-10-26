#!/bin/bash
# check if the `server.xml` file has been changed since the creation of this
# Docker image. If the file has been changed the entrypoint script will not
# perform modifications to the configuration file.

if [ "$(stat --format "%Y" "${BITBUCKET_INSTALL}/conf/server.xml")" -eq "0" ]; then
  echo "Configure server.xml (proxy and context root)"
  if [ -n "${ADOP_PROXYNAME}" ]; then
    xmlstarlet ed --inplace --pf --ps --insert '//Connector[@port="7990"]' --type "attr" --name "proxyName" --value "${ADOP_PROXYNAME}" "${BITBUCKET_INSTALL}/conf/server.xml"
  fi
  if [ -n "${ADOP_PROXYPORT}" ]; then
    xmlstarlet ed --inplace --pf --ps --insert '//Connector[@port="7990"]' --type "attr" --name "proxyPort" --value "${ADOP_PROXYPORT}" "${BITBUCKET_INSTALL}/conf/server.xml"
  fi
  if [ -n "${ADOP_PROXYSCHEME}" ]; then
    xmlstarlet ed --inplace --pf --ps --insert '//Connector[@port="7990"]' --type "attr" --name "scheme" --value "${ADOP_PROXYSCHEME}" "${BITBUCKET_INSTALL}/conf/server.xml"
  fi
  if [ -n "${BITBUCKET_ROOTPATH}" ]; then
    xmlstarlet ed --inplace --pf --ps --update '//Context/@path' --value "${BITBUCKET_ROOTPATH}" "${BITBUCKET_INSTALL}/conf/server.xml"
  fi
fi

echo "Init bitbucket.properties (database)"
# If configuration is present
if [[ -n "${DB_HOST}" && -n "${BITBUCKET_DB}" && -n "${BITBUCKET_DB_USER}" && -n "${BITBUCKET_DB_PASSWORD}" ]];then
	# At the first launch
	if [ ! -f "${BITBUCKET_HOME}/shared/bitbucket.properties" ]; then
		mv "${BITBUCKET_HOME}/shared/bitbucket.properties.template" "${BITBUCKET_HOME}/shared/bitbucket.properties"
	fi
	# Update values
	sed "s|jdbc.url=.*|jdbc.url=jdbc:postgresql://${DB_HOST}:5432/${BITBUCKET_DB}|g" -i "${BITBUCKET_HOME}/shared/bitbucket.properties"
	sed "s|jdbc.user=.*|jdbc.user=${BITBUCKET_DB_USER}|g" -i "${BITBUCKET_HOME}/shared/bitbucket.properties"
	sed "s|jdbc.password=.*|jdbc.password=${BITBUCKET_DB_PASSWORD}|g" -i "${BITBUCKET_HOME}/shared/bitbucket.properties"
	
fi
echo "Checking Postgres availability ..."
until databasesList=$(PGPASSWORD="${DB_POSTGRES_PASSWORD}" psql -h "${DB_HOST}" -p "5432" -U "postgres"  -c '\l'); do
  echo "Postgres is unavailable - sleeping 1s ..."
  sleep 1
done

echo "Postgres is up !"

echo $databasesList | grep -q "${BITBUCKET_DB}"
if [ $? -eq 0 ];then
	echo "Database ${BITBUCKET_DB} already exists."
else
	echo "Create database ${BITBUCKET_DB} ..."
PGPASSWORD="${DB_POSTGRES_PASSWORD}" psql -v ON_ERROR_STOP=1 --username "postgres" --host "${DB_HOST}" --port "5432" <<-EOSQL
    CREATE USER ${BITBUCKET_DB_USER} WITH PASSWORD '${BITBUCKET_DB_PASSWORD}';
    CREATE DATABASE ${BITBUCKET_DB};
    GRANT ALL PRIVILEGES ON DATABASE ${BITBUCKET_DB} TO ${BITBUCKET_DB_USER};
EOSQL
	echo "Database ${BITBUCKET_DB} successfully created."
fi

echo "Configuration and database setup completed successfully, starting Jira Software ..."
	
# With exec, the child process replaces the parent process entirely
# exec is more precise/correct/efficient
exec $@