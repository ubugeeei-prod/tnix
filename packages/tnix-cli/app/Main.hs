{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Command-line entry point for tnix tooling.
--
-- The CLI intentionally stays small: it exposes the three capabilities that are
-- useful both for humans and for editor integration tests, namely compile,
-- check, and declaration emission.
module Main (main) where

import Cli qualified
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Data.Version (showVersion)
import Options.Applicative
import Paths_tnix_cli qualified as PackageInfo
import System.Exit (die, exitFailure)
import System.Process (callProcess)

-- | Parse arguments and execute the requested command.
main :: IO ()
main = execParser opts >>= run
  where
    opts =
      info
        (Cli.commandParser <**> helper <**> versionOption)
        (fullDesc <> progDesc "Compile, check, emit, and scaffold tnix projects")
    versionOption =
      infoOption
        ("tnix " <> showVersion PackageInfo.version)
        (long "version" <> short 'v' <> help "Show the tnix version")

-- | Execute one CLI command.
run :: Cli.Command -> IO ()
run (Cli.Version format) =
  putPayload (Cli.renderVersion (Text.pack (showVersion PackageInfo.version)) format)
run (Cli.Lsp logFile) =
  callProcess "tnix-lsp" (Cli.lspCommandArgs logFile)
run cmd =
  Cli.executeCommand cmd >>= \case
    Left err ->
      case Cli.commandOutputFormat cmd of
        Just Cli.JsonFormat -> TextIO.putStrLn (Text.pack err) >> exitFailure
        _ -> die err
    Right content ->
      case Cli.commandOutputPath cmd of
        Just output -> Cli.writeOutput (Just output) content
        Nothing -> putPayload content

putPayload :: Text.Text -> IO ()
putPayload content =
  if "\n" `Text.isSuffixOf` content
    then TextIO.putStr content
    else TextIO.putStrLn content
