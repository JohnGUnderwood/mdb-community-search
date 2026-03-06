#!/bin/bash
set -e

echo "Starting MongoDB initialization..."

# Use environment variables passed from Docker Compose
export MONGOT_PASSWORD=${MONGOT_PASSWORD:-mongotPassword}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}

echo "Using mongot password from environment variable"
echo "Using admin password from environment variable"

# Wait for MongoDB to be ready
echo "Waiting for MongoDB to be ready..."
until mongosh --eval "print('MongoDB is ready')" > /dev/null 2>&1; do
  echo "Waiting for MongoDB..."
  sleep 2
done

echo "MongoDB is ready, proceeding with initialization..."

# Create mongot user
echo "Creating mongotUser..."
mongosh --eval "
const adminDb = db.getSiblingDB('admin');
try {
  adminDb.createUser({
    user: 'mongotUser',
    pwd: '$MONGOT_PASSWORD',
    roles: [{ role: 'searchCoordinator', db: 'admin' }]
  });
  print('User mongotUser created successfully');
} catch (error) {
  if (error.code === 11000) {
    print('User mongotUser already exists');
  } else {
    print('Error creating user: ' + error);
    throw error;
  }
}
"

# Check for existing sample data and restore if needed
echo "Checking for existing sample data..."
DATA_EXISTS=$(mongosh --quiet --eval "
try {
  const collections = db.getSiblingDB('sample_airbnb').getCollectionNames();
  print(collections.includes('listingsAndReviews'));
} catch (e) {
  print('false');
}
")

if echo "$DATA_EXISTS" | grep -q "true"; then
  echo "Sample data already exists. Skipping restore."
else
  echo "Sample data not found. Running mongorestore..."
  if [ -f "/sampledata.archive" ]; then
    mongorestore --archive=/sampledata.archive
    echo "Sample data restored successfully."
  else
    echo "Warning: sampledata.archive not found at /sampledata.archive"
  fi
fi

echo "MongoDB initialization completed successfully."