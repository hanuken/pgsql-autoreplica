#!/bin/bash
cleanname=$(echo $DESTDBNAME | sed 's/[^a-zA-Z0-9]//g')
subname="${cleanname}sub"
slotname=$subname
pubname="${cleanname}pub"
PGPASSWORD=$SOURCEPASSWD total_publications=$(psql -h "$SOURCESERVER" -U $SOURCEUSER -d $SOURCEDBNAME -t -c "select count(pubname) from pg_publication where pubname='$pubname';")
PGPASSWORD=$SOURCEPASSWD total_active_slots=$(psql -h "$SOURCESERVER" -U $SOURCEUSER -d postgres -t -c "select count(slot_name)from pg_replication_slots where slot_name='$slotname';")


# If exists, drop already created publication (alive publication may cause errors in some cases).
if [ $total_publications -eq 1 ]
then
	PGPASSWORD=$SOURCEPASSWD psql -h "$SOURCESERVER" -U $SOURCEUSER -d $SOURCEDBNAME -t -c "drop publication $pubname";
fi

## If exists, drop active slot for this replica.
#if [ $total_actibe_slots -gt 0 ]
#then
#        PGPASSWORD=$SOURCEPASSWD psql -h "$SOURCESERVER" -U $SOURCEUSER -d postgres -t -c "select pg_drop_replication_slot('$slotname');";
#fi


# Create dump
PGPASSWORD=$SOURCEPASSWD pg_dump -h "$SOURCESERVER" -U $SOURCEUSER --compress=0 --encoding='UTF8' --format=c --dbname="$SOURCEDBNAME" --schema-only >> /tmp/schema.dump

# Create publication on master
PGPASSWORD=$SOURCEPASSWD psql -h "$SOURCESERVER" -U $SOURCEUSER -d $SOURCEDBNAME -t -c "create publication $pubname for all tables";

# Set up replication for replica and create user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "$DESTDBNAME";
    CREATE ROLE "$DESTDBUSER" login password '$DESTDBPASSWORD';
EOSQL

# Restore dump
pg_restore -U $POSTGRES_USER -d "$DESTDBNAME" /tmp/schema.dump

# Set permissions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DESTDBNAME" <<-EOSQL
    GRANT CONNECT ON DATABASE "$DESTDBNAME" TO "$DESTDBUSER";
    GRANT USAGE ON SCHEMA public TO "$DESTDBUSER";
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO "$DESTDBUSER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO "$DESTDBUSER";
EOSQL

# Create subscription and start replication
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DESTDBNAME" <<-EOSQL
    CREATE SUBSCRIPTION "$subname" CONNECTION 'host=$SOURCESERVER port=5432 password=SOURCEPASSWD user=$SOURCEUSER dbname=$SOURCEDBNAME' PUBLICATION "$pubname";
EOSQL
