#!/usr/bin/env bats

AGENT_IMAGE=jenkins-ssh-slave
AGENT_CONTAINER=bats-jenkins-ssh-slave

REGEX='^([0-9]+)/(.+)$'

if [[ ${FOLDER} =~ ${REGEX} ]] && [[ -d "${FOLDER}" ]]
then
  JDK="${BASH_REMATCH[1]}"
  FLAVOR="${BASH_REMATCH[2]}"
else
  echo "Wrong folder format or folder does not exist: ${FOLDER}"
  exit 1
fi

DOCKERFILE="${FOLDER}/Dockerfile"

if [[ "${JDK}" = "11" ]]
then
  AGENT_IMAGE+=":jdk11"
  AGENT_CONTAINER+="-jdk11"
else
  if [[ "${FLAVOR}" = "alpine*" ]]
  then
    AGENT_IMAGE+=":alpine"
    AGENT_CONTAINER+="-alpine"
  else
    AGENT_IMAGE+=":latest"
  fi
fi

load test_helpers
load keys

clean_test_container

function teardown () {
  clean_test_container
}

@test "[${FLAVOR}] build image" {
  cd "${BATS_TEST_DIRNAME}"/.. || false
  docker build -t "${AGENT_IMAGE}" -f "${DOCKERFILE}" "${JDK}"
}

@test "[${FLAVOR}] checking image metadata" {
  local VOLUMES_MAP
  VOLUMES_MAP="$(docker inspect -f '{{.Config.Volumes}}' ${AGENT_IMAGE})"

  echo "${VOLUMES_MAP}" | grep '/tmp'
  echo "${VOLUMES_MAP}" | grep '/home/jenkins'
  echo "${VOLUMES_MAP}" | grep '/run'
  echo "${VOLUMES_MAP}" | grep '/var/run'
}

@test "[${FLAVOR}] image has bash and java installed and in the PATH" {
  docker run -d --name "${AGENT_CONTAINER}" -P "${AGENT_IMAGE}" "${PUBLIC_SSH_KEY}"

  run docker exec "${AGENT_CONTAINER}" which bash
  [ "${status}" -eq 0 ]
  run docker exec "${AGENT_CONTAINER}" bash --version
  [ "${status}" -eq 0 ]
  run docker exec "${AGENT_CONTAINER}" which java
  [ "${status}" -eq 0 ]

  if [[ "${JDK}" -eq 8 ]]
  then
    run docker exec "${AGENT_CONTAINER}" sh -c "
    java -version 2>&1 \
      | grep -o -E '^openjdk version \"[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+.*\"' \
      | grep -o -E '\.[[:digit:]]+\.' \
      | grep -o -E '[[:digit:]]+'
    "
  else
    run docker exec "${AGENT_CONTAINER}" sh -c "
    java -version 2>&1 \
      | grep -o -E '^openjdk version \"[[:digit:]]+\.' \
      | grep -o -E '\"[[:digit:]]+\.' \
      | grep -o -E '[[:digit:]]+'
    "
  fi
  [ "${JDK}" = "${lines[0]}" ]
}

@test "[${FLAVOR}] create slave container with pubkey as argument" {
  docker run -d --name "${AGENT_CONTAINER}" -P "${AGENT_IMAGE}" "${PUBLIC_SSH_KEY}"

  is_slave_container_running

  run_through_ssh echo f00

  [ "$status" = "0" ] && [ "$output" = "f00" ] \
    || (\
      echo "status: $status"; \
      echo "output: $output"; \
      false \
    )
}

@test "[${FLAVOR}] create slave container with pubkey as environment variable" {
  docker run -e "JENKINS_SLAVE_SSH_PUBKEY=${PUBLIC_SSH_KEY}" -d --name "${AGENT_CONTAINER}" -P "${AGENT_IMAGE}"

  is_slave_container_running

  run_through_ssh echo f00

  [ "$status" = "0" ] && [ "$output" = "f00" ] \
    || (\
      echo "status: $status"; \
      echo "output: $output"; \
      false \
    )
}

@test "[${FLAVOR}] use build args correctly" {
  cd "${BATS_TEST_DIRNAME}"/.. || false

	local TEST_USER=test-user
	local TEST_GROUP=test-group
	local TEST_UID=2000
	local TEST_GID=3000
	local TEST_JAH=/home/something

  docker build \
    --build-arg "user=${TEST_USER}" \
    --build-arg "group=${TEST_GROUP}" \
    --build-arg "uid=${TEST_UID}" \
    --build-arg "gid=${TEST_GID}" \
    --build-arg "JENKINS_AGENT_HOME=${TEST_JAH}" \
    -t "${AGENT_IMAGE}" \
    -f "${DOCKERFILE}" \
    "${JDK}"

  docker run -d --name "${AGENT_CONTAINER}" -P "${AGENT_IMAGE}" "${PUBLIC_SSH_KEY}"

  run docker exec "${AGENT_CONTAINER}" sh -c "id -u -n ${TEST_USER}"
  [ "${TEST_USER}" = "${lines[0]}" ]
  run docker exec "${AGENT_CONTAINER}" sh -c "id -g -n ${TEST_USER}"
  [ "${TEST_GROUP}" = "${lines[0]}" ]
  run docker exec "${AGENT_CONTAINER}" sh -c "id -u ${TEST_USER}"
  [ "${TEST_UID}" = "${lines[0]}" ]
  run docker exec "${AGENT_CONTAINER}" sh -c "id -g ${TEST_USER}"
  [ "${TEST_GID}" = "${lines[0]}" ]
  run docker exec "${AGENT_CONTAINER}" sh -c 'stat -c "%U:%G" "${JENKINS_AGENT_HOME}"'
  [ "${TEST_USER}:${TEST_GROUP}" = "${lines[0]}" ]
}
