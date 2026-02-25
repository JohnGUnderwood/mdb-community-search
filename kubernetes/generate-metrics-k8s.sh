#!/usr/bin/env bash

set -euo pipefail

MONGO_URI="mongodb://mdb-admin:${ADMIN_PASSWORD}@mongodb-svc:27017/admin?authSource=admin"

echo "Waiting for MongoDB to become reachable..."
for i in {1..120}; do
  if mongosh "$MONGO_URI" --quiet --eval "db.adminCommand('ping').ok" | grep -q "1"; then
    echo "MongoDB is reachable"
    break
  fi
  sleep 5
done

mongosh "$MONGO_URI" --quiet <<'EOF'
const sample = db.getSiblingDB('sample_mflix');

function vector(size, value) {
  return Array.from({ length: size }, () => value);
}

if (sample.embedded_movies.countDocuments() === 0) {
  print('No sample data found in sample_mflix.embedded_movies. Inserting seed documents...');
  sample.embedded_movies.insertMany([
    {
      title: 'Action Frontier',
      plot: 'A fearless crew explores unknown worlds and faces danger.',
      genres: ['Action', 'Adventure', 'Sci-Fi'],
      cast: ['Alex Stone', 'Jamie Vale'],
      directors: ['Riley Hart'],
      year: 2020,
      plot_embedding_voyage_3_large: vector(2048, 0.01)
    },
    {
      title: 'City of Laughter',
      plot: 'A comedian rediscovers family and purpose in a chaotic city.',
      genres: ['Comedy', 'Drama'],
      cast: ['Sam River', 'Taylor Quinn'],
      directors: ['Jordan Lee'],
      year: 2021,
      plot_embedding_voyage_3_large: vector(2048, 0.02)
    },
    {
      title: 'Midnight Mystery',
      plot: 'A detective unravels clues hidden in old film archives.',
      genres: ['Mystery', 'Thriller'],
      cast: ['Chris West', 'Pat Morgan'],
      directors: ['Avery Knox'],
      year: 2019,
      plot_embedding_voyage_3_large: vector(2048, 0.03)
    },
    {
      title: 'Romance at Dawn',
      plot: 'Two travelers meet by chance and change each other forever.',
      genres: ['Romance', 'Drama'],
      cast: ['Dana Reese', 'Lee Carter'],
      directors: ['Morgan Fox'],
      year: 2022,
      plot_embedding_voyage_3_large: vector(2048, 0.04)
    }
  ]);
} else {
  print('Sample documents already present in sample_mflix.embedded_movies');
}

try {
  const indexes = sample.embedded_movies.getSearchIndexes();
  const textIndexExists = indexes.some((idx) => idx.name === 'text_index');
  if (!textIndexExists) {
    sample.embedded_movies.createSearchIndex(
      'text_index',
      {
        mappings: {
          dynamic: true,
          fields: {
            title: [
              { type: 'string', analyzer: 'lucene.standard' },
              {
                type: 'autocomplete',
                analyzer: 'lucene.standard',
                tokenization: 'edgeGram',
                minGrams: 3,
                maxGrams: 15,
                foldDiacritics: false
              }
            ],
            plot_embedding_voyage_3_large: {
              type: 'vector',
              numDimensions: 2048,
              similarity: 'dotProduct'
            }
          }
        }
      }
    );
    print('Created text_index');
  } else {
    print('text_index already exists');
  }
} catch (e) {
  print('Text index creation skipped/failed: ' + e.message);
}

try {
  const indexes = sample.embedded_movies.getSearchIndexes();
  const vectorIndexExists = indexes.some((idx) => idx.name === 'vector_index');
  if (!vectorIndexExists) {
    sample.embedded_movies.createSearchIndex({
      name: 'vector_index',
      type: 'vectorSearch',
      definition: {
        fields: [
          {
            type: 'vector',
            path: 'plot_embedding_voyage_3_large',
            numDimensions: 2048,
            similarity: 'dotProduct'
          }
        ]
      }
    });
    print('Created vector_index');
  } else {
    print('vector_index already exists');
  }
} catch (e) {
  print('Vector index creation skipped/failed: ' + e.message);
}

const queries = [
  ['action', 5],
  ['comedy', 10],
  ['drama', 15],
  ['adventure', 20],
  ['thriller', 25],
  ['romance', 30],
  ['mystery', 35],
  ['science', 40]
];

for (let round = 0; round < 6; round++) {
  for (const [query, limit] of queries) {
    try {
      const result = sample.embedded_movies.aggregate([
        {
          $search: {
            index: 'text_index',
            text: {
              query,
              path: ['title', 'plot', 'genres', 'cast', 'directors']
            }
          }
        },
        { $limit: limit },
        { $project: { title: 1, year: 1, score: { $meta: 'searchScore' } } }
      ]).toArray();

      print(`round=${round + 1} query='${query}' returned=${result.length}`);
    } catch (e) {
      print(`round=${round + 1} query='${query}' failed: ${e.message}`);
    }
    sleep(1000);
  }
}

print('Metric generation job completed');
EOF
