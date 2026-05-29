-- | Bounded analysis-result cache keyed by @(file path, source content)@.
--
-- Per-buffer analysis is already memoised inside 'Session.Documents', but
-- workspace-wide requests re-read and re-analyse sibling files on every
-- call. This cache lets the second hover / workspace-symbol / definition
-- request reuse the previous result whenever the content has not changed,
-- collapsing what was an O(workspace) cost into O(changed files).
--
-- Entries carry a monotonically increasing sequence number so the cache
-- can be capped at 'analysisCacheCapacity' with simple FIFO eviction. A
-- 'didChange' that changes the document text shifts the key, so stale
-- entries naturally fall out of the working set even before eviction.
module AnalysisCache
  ( AnalysisCache,
    AnalysisKey,
    analysisCacheCapacity,
    analysisCacheSize,
    emptyAnalysisCache,
    insertAnalysisCache,
    lookupAnalysisCache,
  )
where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Text (Text)
import Driver (Analysis)

-- | Cache key: full path + the exact source text the analysis was produced
-- from. Two different files with identical content do not share entries
-- because tnix resolves imports relative to the source path.
type AnalysisKey = (FilePath, Text)

-- | Opaque cache value. Construct with 'emptyAnalysisCache' and mutate via
-- 'insertAnalysisCache'.
data AnalysisCache = AnalysisCache
  { analysisCacheEntries :: !(Map AnalysisKey (Int, Either String Analysis)),
    analysisCacheNext :: !Int
  }
  deriving (Show)

-- | Maximum number of entries kept in the cache. Once exceeded, older
-- entries (lowest sequence numbers) are evicted FIFO.
analysisCacheCapacity :: Int
analysisCacheCapacity = 256

-- | Initial empty cache.
emptyAnalysisCache :: AnalysisCache
emptyAnalysisCache = AnalysisCache Map.empty 0

-- | Current number of cached entries.
analysisCacheSize :: AnalysisCache -> Int
analysisCacheSize = Map.size . analysisCacheEntries

-- | Look up a cached analysis result for the given key.
lookupAnalysisCache :: AnalysisKey -> AnalysisCache -> Maybe (Either String Analysis)
lookupAnalysisCache key cache = snd <$> Map.lookup key (analysisCacheEntries cache)

-- | Insert or replace an analysis result, evicting the oldest entries if
-- the cache would exceed 'analysisCacheCapacity'.
insertAnalysisCache :: AnalysisKey -> Either String Analysis -> AnalysisCache -> AnalysisCache
insertAnalysisCache key value cache =
  let nextSeq = analysisCacheNext cache
      added = Map.insert key (nextSeq, value) (analysisCacheEntries cache)
      bounded =
        if Map.size added > analysisCacheCapacity
          then
            Map.fromList
              ( take
                  analysisCacheCapacity
                  ( sortOn
                      (Down . (\(_, (seqNo, _)) -> seqNo))
                      (Map.toList added)
                  )
              )
          else added
   in AnalysisCache bounded (nextSeq + 1)
