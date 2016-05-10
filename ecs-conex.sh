#!/usr/bin/env bash

set -eu

echo "checking docker configuration"
docker version > /dev/null

echo "checking environment configuration"
Message=${Message}
AccountId=${AccountId}
GithubAccessToken=${GithubAccessToken}
StackRegion=${StackRegion}

echo "parsing received message"
ref=$(node -e "console.log(${Message}.ref);")
after=$(node -e "console.log(${Message}.after);")
before=$(node -e "console.log(${Message}.before);")
repo=$(node -e "console.log(${Message}.repository.name);")
owner=$(node -e "console.log(${Message}.repository.owner.name);")
user=$(node -e "console.log(${Message}.pusher.name);")

regions=(us-east-1 us-west-2 eu-west-1)
tmpdir="/mnt/data/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

function before_image() {
  local region=$1
  echo ${AccountId}.dkr.ecr.${region}.amazonaws.com/${repo}:${before}
}

function after_image() {
  local region=$1
  local sha=${2:-${after}}
  echo ${AccountId}.dkr.ecr.${region}.amazonaws.com/${repo}:${sha}
}

function login() {
  local region=$1
  eval "$(aws ecr get-login --region ${region})"
}

function ensure_repo() {
  local region=$1
  aws ecr describe-repositories \
    --region ${region} \
    --repository-names ${repo} > /dev/null 2>&1 || create_repo ${region}
}

function create_repo() {
  local region=$1
  aws ecr create-repository --region ${region} --repository-name ${repo} > /dev/null
}

function cleanup() {
  rm -rf ${tmpdir}
}

echo "processing commit ${after} by ${user} to ${ref} of ${owner}/${repo}"

git clone https://${GithubAccessToken}@github.com/${owner}/${repo} ${tmpdir}
trap "cleanup" EXIT
cd ${tmpdir} && git checkout -q $after || exit 3

if [ ! -f ./Dockerfile ]; then
  echo "no Dockerfile found"
  exit 0
fi

echo "attempt to fetch previous image from ${StackRegion}"
ensure_repo ${StackRegion}
login ${StackRegion}
docker pull "$(before_image ${StackRegion})" 2> /dev/null || :

echo "building new image"
docker build --tag ${repo} ${tmpdir}

for region in "${regions[@]}"; do
  ensure_repo ${region}
  login ${region}

  echo "pushing ${after} to ${region}"
  docker tag -f ${repo}:latest "$(after_image ${region})"
  docker push "$(after_image ${region})"

  if git describe --tags --exact-match 2> /dev/null; then
    tag="$(git describe --tags --exact-match)"
    echo "pushing ${tag} to ${region}"
    docker tag -f ${repo}:latest "$(after_image ${region} ${tag})"
    docker push "$(after_image ${region} ${tag})"
  fi
done

echo "completed successfully"