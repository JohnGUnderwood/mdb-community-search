#!/bin/bash

# Script to generate search activity for dashboard demonstration
# This will create search indexes and run some search queries to populate the metrics

echo "🔍 Generating Search Activity for Dashboard Demo..."
echo "=================================================="

# Check if MongoDB is accessible
if ! docker compose exec -T mongod mongosh -u admin -p admin --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
  echo "❌ MongoDB is not accessible. Make sure the stack is running with: docker compose up -d"
  exit 1
fi

echo "✅ MongoDB is accessible"

# Check if we have sample data
echo -n "Checking for sample data... "
DB_COUNT=$(docker compose exec -T mongod mongosh -u admin -p admin --authenticationDatabase admin --eval "print(db.adminCommand('listDatabases').databases.filter(d => d.name.startsWith('sample')).length)" --quiet)
if [ "$DB_COUNT" -gt 0 ]; then
  echo "✅ Found $DB_COUNT sample database(s)"
else
  echo "⚠️  No sample databases found. Some queries may not work."
fi

# Create a search index on the sample_airbnb database if it exists
echo ""
echo "📊 Creating search indexes..."
docker compose exec -T mongod mongosh -u admin -p admin --authenticationDatabase admin --eval "
try {
  // Check if sample_airbnb exists
  const dbs = db.adminCommand('listDatabases').databases.map(d => d.name);
  if (dbs.includes('sample_airbnb')) {
    db = db.getSiblingDB('sample_airbnb');
    
    // Create a search index if it doesn't exist
    try {
      const indexExists = db.listingsAndReviews.getSearchIndexes().length > 0;
      if (!indexExists) {
        db.listingsAndReviews.createSearchIndex(
          'default',
          {
            'mappings': {
              'dynamic': true
            }
          }
        );
        print('✅ Search index created on sample_airbnb.listingsAndReviews');
      } else {
        print('✅ Search index already exists on sample_airbnb.listingsAndReviews');
      }
    } catch (e) {
      print('ℹ️  Note: Search index creation requires Atlas Search (mongot) to be fully initialized');
    }
  } else {
    print('ℹ️  sample_airbnb database not found. Skipping index creation.');
  }
} catch (e) {
  print('Error: ' + e);
}" --quiet

echo ""
echo "🔍 Running search queries to generate metrics..."

# Run some search queries to generate metrics
for i in {1..5}; do
  echo "Running search query $i/5..."
  
  docker compose exec -T mongod mongosh -u admin -p admin --authenticationDatabase admin --eval "
  try {
    db = db.getSiblingDB('sample_airbnb');
    if (db.listingsAndReviews.countDocuments() > 0) {
      // Run a text search query
      const result = db.listingsAndReviews.aggregate([
        {
          \$search: {
            text: {
              query: 'apartment',
              path: ['name', 'description']
            }
          }
        },
        { \$limit: 5 },
        { \$project: { name: 1, property_type: 1 } }
      ]);
      print('Search query executed successfully');
    } else {
      print('No documents found in sample_airbnb.listingsAndReviews');
    }
  } catch (e) {
    print('Search query failed (this is normal if mongot is still initializing): ' + e.message);
  }" --quiet 2>/dev/null
  
  sleep 2
done

echo ""
echo "📈 Running some database operations to generate additional metrics..."

# Generate some regular database activity
docker compose exec -T mongod mongosh -u admin -p admin --authenticationDatabase admin --eval "
// Create a test collection and run various operations
db = db.getSiblingDB('dashboard_demo');

// Insert some documents
for (let i = 0; i < 50; i++) {
  db.test_collection.insertOne({
    index: i,
    timestamp: new Date(),
    data: 'Sample data for dashboard demo ' + i
  });
}

// Run some queries
db.test_collection.find({index: {\$gte: 25}}).limit(10).toArray();
db.test_collection.countDocuments();

// Update some documents
db.test_collection.updateMany({index: {\$mod: [10, 0]}}, {\$set: {updated: true}});

// Delete a few documents
db.test_collection.deleteMany({index: {\$gte: 45}});

print('✅ Generated database activity for dashboard metrics');
" --quiet

echo ""
echo "🎯 Testing Prometheus metrics endpoints..."
echo ""

# Test MongoDB Exporter metrics
echo -n "MongoDB Exporter metrics: "
if curl -s http://localhost:9216/metrics | grep -q "mongodb_up"; then
  echo "✅ Available"
else
  echo "❌ Not accessible"
fi

# Test Mongot metrics
echo -n "Mongot metrics: "
if curl -s http://localhost:9946/metrics | grep -q "mongot_"; then
  echo "✅ Available"
else
  echo "❌ Not accessible"
fi

# Test Prometheus query API
echo -n "Prometheus API: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_up" | jq -r '.status' 2>/dev/null | grep -q "success"; then
  echo "✅ Available"
else
  echo "❌ Not accessible"
fi

echo ""
echo "🎉 Dashboard demo setup complete!"
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000 (admin/admin)"
echo "2. Navigate to 'MongoDB Community Search Monitoring' dashboard"
echo "3. You should see metrics from the activity we just generated"
echo "4. Run this script again to generate more activity and see the metrics change"
echo ""
echo "💡 Tip: The dashboard auto-refreshes every 5 seconds, so you'll see new data quickly!"