#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- identity
  CREATE DATABASE identity_v0; CREATE DATABASE identity_v1; CREATE DATABASE identity_v2;
  CREATE DATABASE identity_v3; CREATE DATABASE identity_v4; CREATE DATABASE identity_v5;
  CREATE DATABASE identity_v6;
  -- organization
  CREATE DATABASE organization_v0; CREATE DATABASE organization_v1; CREATE DATABASE organization_v2;
  CREATE DATABASE organization_v3; CREATE DATABASE organization_v4;
  -- authorization
  CREATE DATABASE authorization_v0; CREATE DATABASE authorization_v1; CREATE DATABASE authorization_v2;
  CREATE DATABASE authorization_v3; CREATE DATABASE authorization_v4;
  -- notification
  CREATE DATABASE notification_v0; CREATE DATABASE notification_v1; CREATE DATABASE notification_v2;
  CREATE DATABASE notification_v3; CREATE DATABASE notification_v4; CREATE DATABASE notification_v5;
  -- file-storage
  CREATE DATABASE file_storage_v0; CREATE DATABASE file_storage_v1; CREATE DATABASE file_storage_v2;
  CREATE DATABASE file_storage_v3; CREATE DATABASE file_storage_v4;
  -- integration
  CREATE DATABASE integration_v0; CREATE DATABASE integration_v1; CREATE DATABASE integration_v2;
  CREATE DATABASE integration_v3; CREATE DATABASE integration_v4;
  -- usage-metering
  CREATE DATABASE usage_metering_v0; CREATE DATABASE usage_metering_v1; CREATE DATABASE usage_metering_v2;
  CREATE DATABASE usage_metering_v3; CREATE DATABASE usage_metering_v4;
  -- billing
  CREATE DATABASE billing_v0; CREATE DATABASE billing_v1; CREATE DATABASE billing_v2;
  CREATE DATABASE billing_v3; CREATE DATABASE billing_v4; CREATE DATABASE billing_v5;
  -- payment
  CREATE DATABASE payment_v0; CREATE DATABASE payment_v1; CREATE DATABASE payment_v2;
  CREATE DATABASE payment_v3; CREATE DATABASE payment_v4; CREATE DATABASE payment_v5;
EOSQL
