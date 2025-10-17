#!/bin/bash

# Script to generate search activity for dashboard demonstration
# This will create search indexes and run search queries on sample_mflix data to populate the metrics

# Set default passwords from environment variables
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}

echo "🔍 Generating Search Activity for Dashboard Demo..."
echo "=================================================="

# Check if MongoDB is accessible
if ! docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
  echo "❌ MongoDB is not accessible. Make sure the stack is running with: docker compose up -d"
  exit 1
fi

echo "✅ MongoDB is accessible"

# Check if we have sample data
echo -n "Checking for sample data... "
DB_COUNT=$(docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "print(db.adminCommand('listDatabases').databases.filter(d => d.name.startsWith('sample')).length)" --quiet)
if [ "$DB_COUNT" -gt 0 ]; then
  echo "✅ Found $DB_COUNT sample database(s)"
else
  echo "⚠️  No sample databases found. Some queries may not work."
fi

# Create search indexes on the sample databases if they exist
echo ""
echo "📊 Creating search indexes..."
docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
try {
  const dbs = db.adminCommand('listDatabases').databases.map(d => d.name);
  
  // Create text search index on sample_mflix.embedded_movies
  if (dbs.includes('sample_mflix')) {
    db = db.getSiblingDB('sample_mflix');
    
    // Check if movies collection has a search index with autocomplete
    try {
      const moviesIndexes = db.embedded_movies.getSearchIndexes();
      const textIndexExists = moviesIndexes.some(idx => idx.name === 'text_index');
      
      if (!textIndexExists) {
        db.embedded_movies.createSearchIndex(
          'text_index',
          {
            'mappings': {
              'dynamic': true,
              'fields': {
                'title': [
                  {
                    'type': 'string',
                    'analyzer': 'lucene.standard'
                  },
                  {
                    'type': 'autocomplete',
                    'analyzer': 'lucene.standard',
                    'tokenization': 'edgeGram',
                    'minGrams': 3,
                    'maxGrams': 15,
                    'foldDiacritics': false
                  }
                ],
                'plot_embedding_voyage_3_large': {
                  'type': 'knnVector',
                  'dimensions': 2048,
                  'similarity': 'dotProduct'
                }
              }
            }
          }
        );
        print('✅ Text search index created on sample_mflix.embedded_movies with autocomplete on title and knnVector on plot_embedding_voyage_3_large');
      } else {
        print('✅ Text search index already exists on sample_mflix.embedded_movies');
      }
    } catch (e) {
      print('ℹ️  Note: Text search index creation failed: ' + e.message);
    }
    
    // Check if embedded_movies collection has a vector search index
    try {
      const embeddedIndexes = db.embedded_movies.getSearchIndexes();
      const vectorIndexExists = embeddedIndexes.some(idx => idx.name === 'vector_index');

      if (!vectorIndexExists) {
        db.embedded_movies.createSearchIndex(
          {
            'name': 'vector_index',
            'type':'vectorSearch',
            'definition':{
              'fields': [
                {
                  'type': 'vector',
                  'path': 'plot_embedding_voyage_3_large',
                  'numDimensions': 2048,
                  'similarity': 'dotProduct'
                }
              ]
            }
          }
        );
        print('✅ Vector search index created on sample_mflix.embedded_movies');
      } else {
        print('✅ Vector search index already exists on sample_mflix.embedded_movies');
      }
      
    } catch (e) {
      print('ℹ️  Note: Vector search index creation failed: ' + e.message);
    }
  } else {
    print('ℹ️  sample_mflix database not found. Skipping movie index creation.');
  }
} catch (e) {
  print('Error: ' + e);
}" --quiet

echo ""
echo "🔍 Running search queries to generate metrics..."

# Run diverse movie search queries to populate the new metrics
echo "Running diverse movie search queries with different limits and parameters..."

# Define different query variations to populate metrics using movie data
QUERIES=(
  # Small limit queries (will affect limitPerQuery metric)
  "action:5"
  "comedy:3"
  "drama:2"
  # Medium limit queries  
  "adventure:15"
  "thriller:20"
  "romance:25"
  # Larger limit queries (will affect batchDataSize and numCandidatesPerQuery)
  "fantasy:50"
  "science:75"
  "mystery:100"
  # Compound searches (more candidates)
  "action AND adventure:30"
  "comedy OR romance:40"
)

for i in "${!QUERIES[@]}"; do
  IFS=':' read -r query limit <<< "${QUERIES[$i]}"
  echo "Running search query $((i+1))/${#QUERIES[@]}: '$query' with limit $limit..."
  
  docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
  try {
    db = db.getSiblingDB('sample_mflix');
    if (db.embedded_movies.countDocuments() > 0) {
      // Run text search with varying limits to populate metrics
      const result = db.embedded_movies.aggregate([
        {
          \$search: {
            index: 'text_index',
            text: {
              query: '$query',
              path: ['title', 'plot', 'genres', 'cast', 'directors']
            }
          }
        },
        { \$limit: $limit },
        { \$project: { 
            title: 1, 
            year: 1,
            genres: 1,
            cast: 1,
            plot: 1,
            score: { \$meta: 'searchScore' }
          } 
        }
      ]).toArray();
      print('Search query \"$query\" executed successfully, returned ' + result.length + ' documents');
      if (result.length > 0) {
        print('  Top result: ' + result[0].title + ' (' + (result[0].year || 'Unknown year') + ')');
      }
    } else {
      print('No documents found in sample_mflix.embedded_movies');
    }
  } catch (e) {
    print('Search query failed (this is normal if mongot is still initializing): ' + e.message);
  }" --quiet 2>/dev/null
  
  sleep 1
done

echo ""
echo "🎬 Running movie text search queries to test the new search index..."

# Run text searches on the movies collection using the new text index
MOVIE_QUERIES=(
  "action:10"
  "adventure:15" 
  "comedy:20"
  "drama:25"
  "thriller:30"
  "romance:12"
  "horror:8"
  "fantasy:18"
)

for query_config in "${MOVIE_QUERIES[@]}"; do
  IFS=':' read -r query limit <<< "$query_config"
  echo "Running movie search: '$query' with limit $limit..."
  
  docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
  try {
    db = db.getSiblingDB('sample_mflix');
    if (db.embedded_movies.countDocuments() > 0) {
      // Run text search on movies
      const result = db.embedded_movies.aggregate([
        {
          \$search: {
            index: 'text_index',
            text: {
              query: '$query',
              path: ['title', 'plot', 'genres', 'cast', 'directors']
            }
          }
        },
        { \$limit: $limit },
        { \$project: { 
            title: 1, 
            year: 1,
            genres: 1,
            cast: 1,
            plot: 1,
            score: { \$meta: 'searchScore' }
          } 
        }
      ]).toArray();
      print('Movie search \"$query\" executed successfully, returned ' + result.length + ' documents');
      if (result.length > 0) {
        print('  Top result: ' + result[0].title + ' (' + (result[0].year || 'Unknown year') + ')');
      }
    } else {
      print('No documents found in sample_mflix.embedded_movies');
    }
  } catch (e) {
    print('Movie search query failed: ' + e.message);
  }" --quiet 2>/dev/null
  
  sleep 1
done

echo ""
echo "🔤 Running autocomplete search queries..."

# Test autocomplete functionality
AUTOCOMPLETE_QUERIES=("star" "the" "love" "war" "dark" "super")

for query in "${AUTOCOMPLETE_QUERIES[@]}"; do
  echo "Running autocomplete search for: '$query'..."
  
  docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
  try {
    db = db.getSiblingDB('sample_mflix');
    if (db.embedded_movies.countDocuments() > 0) {
      // Run autocomplete search
      const result = db.embedded_movies.aggregate([
        {
          \$search: {
            index: 'text_index',
            autocomplete: {
              query: '$query',
              path: 'title'
            }
          }
        },
        { \$limit: 10 },
        { \$project: { 
            title: 1, 
            year: 1,
            score: { \$meta: 'searchScore' }
          } 
        }
      ]).toArray();
      print('Autocomplete search \"$query\" executed successfully, returned ' + result.length + ' documents');
      if (result.length > 0) {
        print('  Suggestions: ' + result.slice(0, 3).map(r => r.title).join(', '));
      }
    }
  } catch (e) {
    print('Autocomplete search query failed: ' + e.message);
  }" --quiet 2>/dev/null
  
  sleep 1
done;

echo ""
echo "🔍 Running additional search variations to generate more metric data..."

# Run some faceted searches and compound queries to generate diverse metrics
for i in {1..3}; do
  echo "Running complex search query $i/3..."
  
  docker compose exec -T mongod mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
  try {
    db = db.getSiblingDB('sample_mflix');
    if (db.embedded_movies.countDocuments() > 0) {
      // Run compound movie search (generates more candidate evaluation)
      const result = db.embedded_movies.aggregate([
        {
          \$search: {
            index: 'text_index',
            compound: {
              must: [
                {
                  text: {
                    query: 'adventure',
                    path: ['title', 'plot']
                  }
                }
              ],
              should: [
                {
                  text: {
                    query: 'action',
                    path: ['genres']
                  }
                },
                {
                  range: {
                    path: 'year',
                    gte: 2000,
                    lte: 2020
                  }
                }
              ]
            }
          }
        },
        { \$limit: $((20 + i * 10)) },
        { \$project: { 
            title: 1, 
            year: 1,
            genres: 1,
            cast: 1,
            plot: 1,
            score: { \$meta: 'searchScore' }
          } 
        }
      ]).toArray();
      print('Complex search query executed, returned ' + result.length + ' documents');
      if (result.length > 0) {
        print('  Top result: ' + result[0].title + ' (' + (result[0].year || 'Unknown year') + ')');
      }
    } else {
      print('No documents found in sample_mflix.embedded_movies');
    }
  } catch (e) {
    print('Complex search query failed: ' + e.message);
  }" --quiet 2>/dev/null
  
  sleep 2
done

echo ""
echo "� Running \$search.knnBeta queries to populate candidates and limit metrics..."

# Run vector search queries with different limits and parameters in a single session
docker exec mongod-community mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin sample_mflix --eval "
// Get a few random movie plot embeddings for vector search queries
print('Getting sample embeddings for vector search...');
const sampleMovies = db.embedded_movies.aggregate([
  { \$sample: { size: 5 } },
  { \$project: { title: 1, plot_embedding_voyage_3_large: 1 } }
]).toArray();

print('✅ Retrieved ' + sampleMovies.length + ' sample embeddings for vector search');
sampleMovies.forEach(movie => print('  - ' + movie.title));

if (sampleMovies.length > 0) {
  const vectorLimits = [10, 25, 50, 100, 150];
  
  for (let i = 0; i < vectorLimits.length; i++) {
    const limit = vectorLimits[i];
    const queryMovie = sampleMovies[i % sampleMovies.length];
    
    if (queryMovie.plot_embedding_voyage_3_large) {
      print('Running knnBeta search query ' + (i+1) + '/' + vectorLimits.length + ' with limit ' + limit + '...');
      
      try {
        const result = db.embedded_movies.aggregate([
          {
            \$search: {
              index: 'text_index',
              knnBeta: {
                vector: Array.from(queryMovie.plot_embedding_voyage_3_large.toFloat32Array()),
                path: 'plot_embedding_voyage_3_large',
                k: limit * 2
              }
            }
          },
          { \$limit: limit },
          {
            \$project: {
              title: 1,
              year: 1,
              genres: 1,
              score: { \$meta: 'searchScore' }
            }
          }
        ]).toArray();
        
        print('  ✅ knnBeta search with limit ' + limit + ' (k: ' + (limit * 2) + ') executed, returned ' + result.length + ' documents');
        if (result.length > 0) {
          print('    Best match: ' + result[0].title + ' (score: ' + result[0].score.toFixed(4) + ')');
        }
      } catch (e) {
        print('  ❌ knnBeta search query failed: ' + e.message);
      }
    } else {
      print('  ⚠️  No embedding found for movie: ' + queryMovie.title);
    }
  }
} else {
  print('❌ No sample movies found for vector search');
}
" --quiet

echo ""
echo "🔬 Running equivalent \$vectorSearch queries with different limits..."

# Run $vectorSearch queries with different limits and parameters in a single session
docker exec mongod-community mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin sample_mflix --eval "
// Get a few random movie plot embeddings for vector search queries
print('Getting sample embeddings for \$vectorSearch...');
const sampleMovies = db.embedded_movies.aggregate([
  { \$sample: { size: 5 } },
  { \$project: { title: 1, plot_embedding_voyage_3_large: 1 } }
]).toArray();

print('✅ Retrieved ' + sampleMovies.length + ' sample embeddings for \$vectorSearch');
sampleMovies.forEach(movie => print('  - ' + movie.title));

if (sampleMovies.length > 0) {
  const vectorLimits = [10, 25, 50, 100, 150];
  
  for (let i = 0; i < vectorLimits.length; i++) {
    const limit = vectorLimits[i];
    const queryMovie = sampleMovies[i % sampleMovies.length];
    
    if (queryMovie.plot_embedding_voyage_3_large) {
      print('Running \$vectorSearch query ' + (i+1) + '/' + vectorLimits.length + ' with limit ' + limit + '...');
      
      try {
        const result = db.embedded_movies.aggregate([
          {
            \$vectorSearch: {
              index: 'vector_index',
              path: 'plot_embedding_voyage_3_large',
              queryVector: queryMovie.plot_embedding_voyage_3_large,
              numCandidates: limit * 2,
              limit: limit
            }
          },
          {
            \$project: {
              title: 1,
              year: 1,
              genres: 1,
              score: { \$meta: 'vectorSearchScore' }
            }
          }
        ]).toArray();
        
        print('  ✅ \$vectorSearch with limit ' + limit + ' (candidates: ' + (limit * 2) + ') executed, returned ' + result.length + ' documents');
        if (result.length > 0) {
          print('    Best match: ' + result[0].title + ' (score: ' + result[0].score.toFixed(4) + ')');
        }
      } catch (e) {
        print('  ❌ \$vectorSearch query failed: ' + e.message);
      }
    } else {
      print('  ⚠️  No embedding found for movie: ' + queryMovie.title);
    }
  }
} else {
  print('❌ No sample movies found for \$vectorSearch');
}
" --quiet

echo ""
echo "🎯 Running additional knnBeta search variations with higher k values..."

# Run some knnBeta searches with much higher k values to really populate the metrics
docker exec mongod-community mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin sample_mflix --eval "
// Get a sample movie embedding for high-candidate vector searches
const sampleMovie = db.embedded_movies.findOne({plot_embedding_voyage_3_large: {\$exists: true}});

if (sampleMovie && sampleMovie.plot_embedding_voyage_3_large) {
  print('Using embedding from: ' + sampleMovie.title);
  
  const highCandidateConfigs = [
    {limit: 20, k: 200},
    {limit: 30, k: 500},
    {limit: 50, k: 1000},
    {limit: 75, k: 1500}
  ];
  
  for (let i = 0; i < highCandidateConfigs.length; i++) {
    const config = highCandidateConfigs[i];
    print('Running high-k knnBeta search: limit=' + config.limit + ', k=' + config.k + '...');
    
    try {
      const result = db.embedded_movies.aggregate([
        {
          \$search: {
            index: 'text_index',
            knnBeta: {
              vector: Array.from(sampleMovie.plot_embedding_voyage_3_large.toFloat32Array()),
              path: 'plot_embedding_voyage_3_large',
              k: config.k
            }
          }
        },
        { \$limit: config.limit },
        {
          \$project: {
            title: 1,
            year: 1,
            plot: 1,
            score: { \$meta: 'searchScore' }
          }
        }
      ]).toArray();
      
      print('  ✅ High-k knnBeta search returned ' + result.length + ' documents');
      if (result.length > 0) {
        print('    Best match: ' + result[0].title + ' (score: ' + result[0].score.toFixed(4) + ')');
      }
    } catch (e) {
      print('  ❌ High-k knnBeta search failed: ' + e.message);
    }
  }
} else {
  print('❌ No movies with embeddings found for high-candidate vector search');
}
" --quiet