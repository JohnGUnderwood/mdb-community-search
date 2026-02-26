#!/usr/bin/env bash

set -euo pipefail

ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
K8S_NAMESPACE="${K8S_NAMESPACE:-mongodb}"
K8S_MONGOD_POD="${K8S_MONGOD_POD:-mongodb-0}"
K8S_MONGOD_CONTAINER="${K8S_MONGOD_CONTAINER:-mongod}"
POD_ARCHIVE_PATH="${POD_ARCHIVE_PATH:-/tmp/sampledata.archive}"
RESTORE_NS_INCLUDE="${RESTORE_NS_INCLUDE:-}"

run_mongosh_admin() {
  kubectl exec -i -n "${K8S_NAMESPACE}" "${K8S_MONGOD_POD}" -c "${K8S_MONGOD_CONTAINER}" -- \
    mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin "$@"
}

run_mongorestore_archive() {
  local restore_args=(
    "--archive=${POD_ARCHIVE_PATH}"
    "--username=admin"
    "--password=${ADMIN_PASSWORD}"
    "--authenticationDatabase=admin"
    "--host=localhost"
    "--port=27017"
  )

  if [ -n "${RESTORE_NS_INCLUDE}" ]; then
    restore_args+=("--nsInclude=${RESTORE_NS_INCLUDE}")
  fi

  kubectl exec -i -n "${K8S_NAMESPACE}" "${K8S_MONGOD_POD}" -c "${K8S_MONGOD_CONTAINER}" -- \
    mongorestore "${restore_args[@]}"
}

copy_archive_to_pod() {
  kubectl cp "sampledata.archive" "${K8S_NAMESPACE}/${K8S_MONGOD_POD}:${POD_ARCHIVE_PATH}" -c "${K8S_MONGOD_CONTAINER}"
}

cleanup_archive_in_pod() {
  kubectl exec -i -n "${K8S_NAMESPACE}" "${K8S_MONGOD_POD}" -c "${K8S_MONGOD_CONTAINER}" -- \
    rm -f "${POD_ARCHIVE_PATH}" >/dev/null 2>&1 || true
}

get_listings_count() {
  run_mongosh_admin --quiet --eval "
try {
  print(db.getSiblingDB('sample_airbnb').getCollection('listingsAndReviews').countDocuments({}));
} catch (e) {
  print(0);
}
" | tr -dc '0-9'
}

# Check for existing sample data and restore if needed
echo "Checking for existing sample data..."
DOC_COUNT="$(get_listings_count)"
DOC_COUNT="${DOC_COUNT:-0}"

if [ "${DOC_COUNT}" -gt 0 ]; then
  echo "Sample data already exists. sample_airbnb.listingsAndReviews count: ${DOC_COUNT}. Skipping restore."
else
  if [ -n "${RESTORE_NS_INCLUDE}" ]; then
    echo "Sample data missing (or empty). Running mongorestore with --nsInclude=${RESTORE_NS_INCLUDE}..."
  else
    echo "Sample data missing (or empty). Running full-archive mongorestore..."
  fi

  if [ -f "sampledata.archive" ]; then
    echo "Copying sampledata.archive to pod ${K8S_MONGOD_POD}:${POD_ARCHIVE_PATH}..."
    copy_archive_to_pod

    cleanup_needed=true
    trap 'if [ "${cleanup_needed:-false}" = "true" ]; then cleanup_archive_in_pod; fi' EXIT

    run_mongorestore_archive

    DOC_COUNT="$(get_listings_count)"
    DOC_COUNT="${DOC_COUNT:-0}"

    if [ "${DOC_COUNT}" -eq 0 ]; then
      echo "❌ Sample data restore completed, but sample_airbnb.listingsAndReviews has 0 documents."
      if [ -n "${RESTORE_NS_INCLUDE}" ]; then
        echo "   Restore namespace filter used: ${RESTORE_NS_INCLUDE}"
        echo "   Verify that sampledata.archive contains sample_airbnb data and the namespace filter matches the archive."
      else
        echo "   Restore mode: full archive"
        echo "   Verify sampledata.archive contains sample_airbnb data."
      fi
      exit 1
    fi

    cleanup_archive_in_pod
    cleanup_needed=false

    echo "Sample data restored successfully. Document count: ${DOC_COUNT}"
  else
    echo "Warning: sampledata.archive not found at sampledata.archive"
  fi
fi
