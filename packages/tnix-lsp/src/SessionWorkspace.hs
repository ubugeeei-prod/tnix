{-# LANGUAGE OverloadedStrings #-}

-- | Workspace-traversal helpers used by the LSP session.
--
-- These functions answer two questions that come up repeatedly during
-- workspace-wide LSP requests:
--
-- 1. Given a buffer URI, where does its tnix workspace start?
-- 2. Given a workspace root, which @.tnix@ / @.d.tnix@ files should the
--    server consider?
--
-- They are intentionally pure of any session-specific types so they can be
-- unit-tested directly and reused outside of `Session.hs`.
module SessionWorkspace
  ( -- * Discovery
    findBuiltinsFile,
    findWorkspaceRoot,
    hasWorkspaceMarker,
    workspaceFilesFor,

    -- * Filters used during traversal
    ignoredDirectory,
    isSourceFile,
  )
where

import Control.Monad (forM)
import Data.List (isPrefixOf, isSuffixOf, nub, sortOn)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (normalise, takeDirectory, (</>))

-- | All @.tnix@ / @.d.tnix@ files relevant to the buffer at @file@.
--
-- If @file@ sits inside a tnix workspace (marked by `hasWorkspaceMarker`),
-- the result is the de-duplicated sorted list of source files under that
-- root. Otherwise the file itself is returned so single-file editing keeps
-- working without a project.
workspaceFilesFor :: FilePath -> IO [FilePath]
workspaceFilesFor file
  | null file = pure []
  | otherwise = do
      root <- findWorkspaceRoot file
      marked <- hasWorkspaceMarker root
      if marked
        then sortOn id . nub <$> go root
        else pure [normalise file]
  where
    go dir = do
      names <- sortOn id <$> listDirectory dir
      fmap concat . forM names $ \name -> do
        let path = normalise (dir </> name)
        isDir <- doesDirectoryExist path
        if isDir
          then
            if ignoredDirectory name
              then pure []
              else go path
          else
            if isSourceFile name
              then pure [path]
              else pure []

-- | Walk parent directories until a workspace marker is found.
--
-- Falls back to the immediate parent directory of @path@ if no marker is
-- ever reached, matching the previous behavior in `Session.hs`.
findWorkspaceRoot :: FilePath -> IO FilePath
findWorkspaceRoot path = go start
  where
    start = normalise (takeDirectory path)
    go dir = do
      marked <- hasWorkspaceMarker dir
      let parent = normalise (takeDirectory dir)
      if marked
        then pure dir
        else
          if parent == dir
            then pure start
            else go parent

-- | A directory is treated as a workspace root if it carries one of the
-- well-known project markers: a flake, cabal-project, pnpm workspace,
-- tnix project config, or a git repository.
hasWorkspaceMarker :: FilePath -> IO Bool
hasWorkspaceMarker dir =
  or
    <$> sequence
      [ doesFileExist (dir </> "flake.nix"),
        doesFileExist (dir </> "cabal.project"),
        doesFileExist (dir </> "pnpm-workspace.yaml"),
        doesFileExist (dir </> "tnix.config.tnix"),
        doesDirectoryExist (dir </> ".git")
      ]

-- | Climb the parent chain looking for a @builtins.d.tnix@ next to the
-- file. Returns the first match closest to the file, or 'Nothing' if the
-- root of the filesystem is reached.
findBuiltinsFile :: FilePath -> IO (Maybe FilePath)
findBuiltinsFile file = go (normalise (takeDirectory file))
  where
    go dir = do
      let candidate = dir </> "builtins.d.tnix"
          parent = normalise (takeDirectory dir)
      exists <- doesFileExist candidate
      if exists
        then pure (Just candidate)
        else
          if parent == dir
            then pure Nothing
            else go parent

-- | Directory names that the workspace walker skips entirely.
--
-- Anything starting with @result@ is treated as a Nix build symlink so
-- @result-doc@, @result-1@, and friends are all excluded.
ignoredDirectory :: FilePath -> Bool
ignoredDirectory name =
  name `elem` [".git", ".direnv", ".devenv", "node_modules", "dist"]
    || "result" `isPrefixOf` name

-- | Predicate for files the workspace walker considers source files.
--
-- This is intentionally simple — both @.tnix@ and @.d.tnix@ pass because
-- @.d.tnix@ is a suffix of @.tnix@.
isSourceFile :: FilePath -> Bool
isSourceFile name = ".tnix" `isSuffixOf` name
