{-| Types expressing some form of text content stored in files. The content can
itself be structured, i.e. in Yaml, JSON or Erlang Term format, or unstructured
raw strings or even binaries. -}
module B9.Content (module X, FileSpec(..), fileSpec, Content(..))
       where

import           Control.Parallel.Strategies
import           Data.Binary
import           Data.Data
import           Data.Hashable
import           GHC.Generics (Generic)
#if !MIN_VERSION_base(4,8,0)
import           Control.Applicative
#endif
import           B9.Content.AST as X
import           B9.Content.ErlTerms as X
import           B9.Content.ErlangPropList as X
import           B9.Content.StringTemplate as X
import           B9.Content.YamlObject as X
import qualified Data.ByteString.Char8 as B
import           B9.QCUtil
import           Test.QuickCheck

-- | This contains most of the information elements necessary to specify a file
-- in some file system. This is used to specify where e.g. cloud-init or the
-- 'LibVirtLXC' builder should create a file.
data FileSpec = FileSpec
    { fileSpecPath :: FilePath
    , fileSpecPermissions :: (Word8, Word8, Word8)
    , fileSpecOwner :: String
    , fileSpecGroup :: String
    } deriving (Read,Show,Eq,Data,Typeable,Generic)

-- | A file spec for a file belonging to root:root with permissions 0644.
fileSpec :: FilePath -> FileSpec
fileSpec f = FileSpec f (6,4,4) "root" "root"

instance Hashable FileSpec
instance Binary FileSpec
instance NFData FileSpec

{- TODO
data Content
    = ErlangContent (AST Content ErlangPropList)
    | YamlContent (AST Content YamlObject)
    | StringContent String
    | FileContent SourceFile
    deriving (Read,Show,Typeable,Eq,Data,Generic)
-}

-- | This defines the contents of a file to be created by B9.
data Content
    = RenderErlang (AST Content ErlangPropList)
    | RenderYaml (AST Content YamlObject)
    | FromString String
    | FromTextFile SourceFile
    deriving (Read,Show,Typeable,Eq,Data,Generic)

instance Hashable Content
instance Binary Content
instance NFData Content

instance CanRender Content where
  render (RenderErlang ast) = encodeSyntax <$> fromAST ast
  render (RenderYaml ast) = encodeSyntax <$> fromAST ast
  render (FromTextFile s) = readTemplateFile s
  render (FromString str) = return (B.pack str)

-- * QuickCheck helper

instance Arbitrary FileSpec where
    arbitrary =
        FileSpec <$> smaller arbitraryFilePath <*>
        ((,,) <$> elements [0 .. 7] <*> elements [0 .. 7] <*> elements [0 .. 7]) <*>
        elements ["root", "alice", "bob"] <*>
        elements ["root", "users", "wheel"]

instance Arbitrary Content where
    arbitrary =
        oneof
            [ FromTextFile <$> smaller arbitrary
            , RenderErlang <$> smaller arbitrary
            , RenderYaml <$> smaller arbitrary
            , FromString <$> smaller arbitrary]