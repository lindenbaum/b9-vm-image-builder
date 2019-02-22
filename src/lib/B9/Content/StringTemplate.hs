{-# LANGUAGE FlexibleContexts #-}

{-| Utility functions based on 'Data.Text.Template' to offer @ $var @ variable
    expansion in string throughout a B9 artifact. -}
module B9.Content.StringTemplate
  ( subst
  , substE
  , substEB
  , substFile
  , substPath
  , readTemplateFile
  , SourceFile(..)
  , SourceFileConversion(..)
  ) where
#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif
import B9.Content.Environment
import B9.QCUtil
import Control.Exception (SomeException)
import Control.Monad.IO.Class (MonadIO(liftIO))
import Control.Monad.Reader (runReaderT)
import Control.Monad.Trans.Identity ()
import Control.Parallel.Strategies
import Data.Bifunctor
import Data.Binary
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
import Data.Data
import Data.Hashable
import qualified Data.Text as T
import Data.Text.Encoding as E
import Data.Text.Lazy.Encoding as LE
import Data.Text.Template (render, renderA, templateSafe)
import GHC.Generics (Generic)
import System.IO.B9Extras
import Test.QuickCheck
import Text.Printf

-- | A wrapper around a file path and a flag indicating if template variable
-- expansion should be performed when reading the file contents.
data SourceFile =
  Source SourceFileConversion
         FilePath
  deriving (Read, Show, Typeable, Data, Eq, Generic)

instance Hashable SourceFile

instance Binary SourceFile

instance NFData SourceFile

data SourceFileConversion
  = NoConversion
  | ExpandVariables
  deriving (Read, Show, Typeable, Data, Eq, Generic)

instance Hashable SourceFileConversion

instance Binary SourceFileConversion

instance NFData SourceFileConversion

readTemplateFile :: (MonadIO m, MonadEnvironment m) => SourceFile -> m B.ByteString
readTemplateFile (Source conv f') = do
  env <- askEnvironment
  case substE env f' of
    Left e ->
      error
        (printf
           "Failed to substitute templates in source \
                    \file name '%s'/\nError: %s\n"
           f'
           e)
    Right f -> do
      c <- liftIO (B.readFile f)
      convert f c
  where
    convert f c =
      case conv of
        NoConversion -> return c
        ExpandVariables -> do
          env <- askEnvironment
          case substEB env c of
            Left e -> error (printf "readTemplateFile '%s' failed: \n%s\n" f e)
            Right c' -> return c'

-- String template substitution via dollar
subst :: Environment -> String -> String
subst env templateStr =
  case substE env templateStr of
    Left e -> error e
    Right r -> r

-- String template substitution via dollar
substE :: Environment -> String -> Either String String
substE env templateStr = second (T.unpack . E.decodeUtf8) (substEB env (E.encodeUtf8 (T.pack templateStr)))

-- String template substitution via dollar
substEB :: Environment -> B.ByteString -> Either String B.ByteString
substEB env templateStr = do
  t <- template'
  res <- renderA t env'
  return (LB.toStrict (LE.encodeUtf8 res))
  where
    env' t =
      case lookupEither t env of
        Right v -> Right v
        Left e -> Left (show e ++ "\nIn template: \"" ++ show templateStr ++ "\"\n")
    template' =
      case templateSafe (E.decodeUtf8 templateStr) of
        Left (row, col) ->
          Left
            ("Invalid template, error at row: " ++ show row ++ ", col: " ++ show col ++ " in: \"" ++ show templateStr)
        Right t -> Right t

substFile :: MonadIO m => Environment -> FilePath -> FilePath -> m ()
substFile env src dest = do
  templateBs <- liftIO (B.readFile src)
  let t = templateSafe (E.decodeUtf8 templateBs)
  case t of
    Left (r, c) ->
      let badLine = unlines (take r (lines (T.unpack (E.decodeUtf8 templateBs))))
          colMarker = replicate (c - 1) '-' ++ "^"
       in error (printf "Template error in file '%s' line %i:\n\n%s\n%s\n" src r badLine colMarker)
    Right template' -> do
      let out = LE.encodeUtf8 (render template' envLookup)
      liftIO (LB.writeFile dest out)
      return ()
  where
    envLookup :: T.Text -> T.Text
    envLookup x = either err id (runReaderT (lookupOrThrow x) env)
      where
        err :: SomeException -> a
        err e = error (show e ++ "\nIn file: \'" ++ src ++ "\'\n")

substPath :: Environment -> SystemPath -> SystemPath
substPath env src =
  case src of
    Path p -> Path (subst env p)
    InHomeDir p -> InHomeDir (subst env p)
    InB9UserDir p -> InB9UserDir (subst env p)
    InTempDir p -> InTempDir (subst env p)

instance Arbitrary SourceFile where
  arbitrary = Source <$> elements [NoConversion, ExpandVariables] <*> smaller arbitraryFilePath