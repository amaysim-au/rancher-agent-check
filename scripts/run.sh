#! /bin/sh

# Verify ENV var inputs
if [ -n "$RANCHER_API_KEY" ]; then
    echo "RANCHER_API_KEY: ** Provided **"
else
    echo "RANCHER_API_KEY: Missing"
    echo .
    echo "This script requires the Rancher API Key to be Provided"
    echo .
    echo "The Rancher API Key needs to have sufficent privileges for"
    echo "the inputed Rancher Environment $[RANCHER_ENV}"
    exit 1
fi

if [ -n "${RANCHER_ENV}" ]; then
    echo "RANCHER_ENV: ${RANCHER_ENV}"
else
    echo "RANCHER_ENV: Missing"
    echo .
    echo "This is a mandatory ENV var"
    echo .
    echo "Must match an existing Rancher Environment configured on the Rancher Server"
    exit 1;
fi

if [ -n "${RANCHER_HOST}" ]; then
    echo "RANCHER_HOST: ${RANCHER_HOST}"
else
    echo "RANCHER_HOST: Missing"
    echo .
    echo "This is a mandatory ENV var"
    echo .
    echo "Must be the HOST or IP of the Rancher Server or Rancher Server Load Balancer"
    exit 1;
fi

if [ -n "${RANCHER_TAGS}" ]; then
    echo "RANCHER_TAGS: ${RANCHER_TAGS}"
else
    echo "RANCHER_TAGS: Missing"
    echo .
    echo "This is an optional ENV var, so no harm done"
    echo .
    echo "If Populated it must be in the form:"
    echo "key1=val1&key2=val2"
fi

if [ "${RANCHER_HTTP_SCHEME}" == "http" ]; then
    HTTP_SCHEME="http"
elif [ "${RANCHER_HTTP_SCHEME}" == "HTTP" ]; then
    HTTP_SCHEME="http"
else
    HTTP_SCHEME="https"
fi

# Check that the required locations have been Volumed in
if [ -S "/var/run/docker.sock" ]; then
    echo "Socket '/var/run/docker.sock' has been volumed in"
else
    echo "The container must have be run with the argument '-v /var/run/docker.sock:/var/run/docker.sock'"
    exit 1
fi

if [ -d "/var/lib/rancher" ]; then
    echo "Directory '/var/lib/rancher' has been volumed in"
else
    echo "The container must have be run with the argument '-v /var/lib/rancher:/var/lib/rancher'"
    exit 1
fi

if [ -f "/etc/hostname" ]; then
    echo "File '/etc/hostname' has been volumed in"
else
    echo "The container must have be run with the argument '-v /etc/hostname:/etc/hostname'"
    exit 1
fi

if [ -f "/var/lib/rancher/engine/docker" ]; then
    echo "Found the 'docker' executable"
    DOCKER=/var/lib/rancher/engine/docker
else
    echo "Unable to find 'docker' executable"
    exit 1
fi

# Get Project ID
RESULT=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/projects")
PROJECT_ID=$(echo "${RESULT}" | jq -r ".data[] | select( .name == \"${RANCHER_ENV}\" ) | .id")
echo "PROJECT_ID: ${PROJECT_ID}"
if [ -z "${PROJECT_ID}" ]; then
	echo "Unable to get the Project ID."
	echo "Perhaps the API key is incorrect."
	echo "HTTP Result:"
	echo ${RESULT}
	exit 1
fi

# Get the hostname
HOSTNAME=$(cat /etc/hostname)
echo "HOSTNAME: ${HOSTNAME}"

# Initial sleep for registration to take place
sleep 300

# Infinite loop checking for rancher-agent
while true; do
    AGENT_STATE=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/projects/${PROJECT_ID}/hosts" |jq -r ".data[] | select(.hostname == \"${HOSTNAME}\") |.agentState")
    echo "AGENT_STATE: ${AGENT_STATE}"
    if [ "${AGENT_STATE}" == "disconnected" ] || [ "${AGENT_STATE}" == "reconnecting" ]; then
        echo "AGENT DISCONNECTED: restarting agent"
        ${DOCKER} restart rancher-agent
        sleep 60
    fi
    sleep 10
done
