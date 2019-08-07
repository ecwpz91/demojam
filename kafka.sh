#!/bin/bash

# Create a secure fifo relative to the user's choice of 'TMPDIR', but falling
# back to the current directory rather than '/tmp'.
tmpd="$(mktemp --directory --tmpdir "${TMPDIR:-.}/kafka.XXXX")" || exit 1

# Download strimzi operator.
curl -L 'https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.13.0/strimzi-0.13.0.tar.gz' \
| tar -xvzf - -C "$tmpd" --strip 1 &>/dev/null

# Configure openshift.
if ! oc whoami &>/dev/null; then
printf "Type the server URL that you want to log in to, followed by [ENTER]: "

read url

if [[ -z "$url" ]]; then
printf "OpenShift server URL cannot be null. Please try with a valid URL..."
exit 1
fi

oc login "$url"

printf "Type cluster administrator username, followed by [ENTER]: "

read admin_user

printf "Type cluster administrator password, followed by [ENTER]: "

read admin_pass
fi

# Gather username for project suffix
PRJ_SUFFIX=${ARG_PROJECT_SUFFIX:-`echo $(oc $ARG_OC_OPS whoami) | sed -e 's/[-@].*//g'`}

# Create user project.
oc new-project kafka-$PRJ_SUFFIX

# Modify the installation files according to the namespace the Cluster Operator is going to be installed in.
sed -i "s/namespace: .*/namespace: kafka-$PRJ_SUFFIX/" $tmpd/install/cluster-operator/*RoleBinding*.yaml

if [[ ! -z "$admin_user" ]] && [[ ! -z "$admin_pass" ]]; then
 oc login "$url" --username "$admin_user" --password "$admin_pass" &>/dev/null

 # Deploy the Cluster Operator.
 oc apply -f $tmpd/install/cluster-operator -n kafka-$PRJ_SUFFIX
 oc apply -f $tmpd/examples/templates/cluster-operator -n kafka-$PRJ_SUFFIX

 # Deploy the Kafka cluster.
 oc apply -f $tmpd/examples/kafka/kafka-ephemeral.yaml -n kafka-$PRJ_SUFFIX

 # Deploy Kafka Connect to your cluster.
 oc apply -f $tmpd/examples/kafka-connect/kafka-connect.yaml -n kafka-$PRJ_SUFFIX

 # Create and deploy a Kafka Connect S2I cluster
 oc apply -f $tmpd/examples/kafka-connect/kafka-connect-s2i.yaml -n kafka-$PRJ_SUFFIX

 mkdir -p ./my-plugins/debezium-connector-postgres

 # Download the latest connector plugins archive for  are available from Maven
 curl -L 'https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/0.9.5.Final/debezium-connector-postgres-0.9.5.Final-plugin.tar.gz' \
 | tar -xvzf - -C "./my-plugins/debezium-connector-postgres" --strip 1 &>/dev/null

 # [TODO]: Wait until deployment is complete.

 # Use the oc start-build command to start a new build of the image using the prepared directory.
 # oc start-build my-connect-cluster-connect --from-dir ./my-plugins/ -n kafka-$PRJ_SUFFIX
fi

# Log out of the active session.
oc logout

# Clean up on exit.
# rm -rf "$tmpd"
